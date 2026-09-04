# frozen_string_literal: true

require_relative "arcade_content"
require_relative "../../lib/english_arcade/scheduler"

class ArcadeProgressDashboard
  AXES = ArcadeExerciseEvent::AXES.freeze
  STAGES = ArcadeLessonComposer::STAGES.freeze

  def initialize(learner_key: "anonymous", content: nil, clock: -> { Time.current })
    @learner_key = learner_key.to_s.presence || "anonymous"
    @content = content || ArcadeContent.new
    @clock = clock
  end

  def call
    now = @clock.call
    states = ArcadeStageState.where(learner_key: @learner_key).to_a
    events = ArcadeExerciseEvent.where(learner_key: @learner_key).where(answered_at: 30.days.ago(now)..).to_a
    lessons = ArcadeLesson.where(learner_key: @learner_key).where(started_at: 14.days.ago(now)..)
    {
      "streak_days" => streak_days(events, now: now),
      "due" => due_summary(states, now: now),
      "mastery_by_target" => mastery_by_target(states, events),
      "accuracy_by_axis_30d" => accuracy_by_axis(events),
      "top_confusions_30d" => top_confusions(events),
      "retention" => retention(states, events, now: now),
      "response_ms_by_stage_30d" => response_times(events),
      "accuracy_by_stage_30d" => stage_accuracy(events),
      "lessons_14d" => lessons.count,
      "minutes_today" => minutes_today(lessons, now: now),
      "recent_lapses" => recent_lapses(events),
      "targets" => target_metadata
    }
  end

  alias dashboard call

  private

  def target_metadata
    @content.targets.each_with_object({}) do |target, result|
      result[target] = { "items" => @content.items_for(target).length }
    end
  end

  def streak_days(events, now:)
    dates = events.map { |event| event.answered_at&.to_date }.compact.uniq.sort.reverse
    return 0 if dates.empty?

    current = now.to_date
    return 0 unless dates.first == current || dates.first == current - 1.day

    count = 1
    dates.each_cons(2) do |newer, older|
      break unless newer - older == 1

      count += 1
    end
    count
  end

  def due_summary(states, now:)
    due = states.select { |state| state.due_at && state.due_at <= now }
    {
      "total" => due.length,
      "by_target" => due.group_by(&:target).transform_values(&:length),
      "overdue" => due.count { |state| state.due_at < now.beginning_of_day },
      "forecast_7d" => states.count { |state| state.due_at && state.due_at <= now + 7.days }
    }
  end

  def mastery_by_target(states, events)
    cards = states.group_by { |state| [ state.target.to_s, state.card_key.to_s ] }
    scores = cards.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((target, _card), rows), result|
      result[target] << mastery_score(rows)
    end
    @content.targets.each_with_object({}) do |target, result|
      values = scores[target]
      item_count = @content.items_for(target).length
      result[target] = {
        "score" => item_count.zero? ? 0.0 : (values.sum / item_count).round(4),
        "items" => item_count,
        "mastered" => values.count { |score| score >= 1.0 },
        "weakest_axis" => weakest_axis(target, events)
      }
    end
  end

  def mastery_score(states)
    weights = { "recognize" => 1.0, "trap" => 1.0, "cloze" => 2.0, "rebuild" => 2.0, "produce" => 3.0, "transfer" => 3.0 }
    stage_targets = { "recognize" => 7.0, "trap" => 7.0, "cloze" => 14.0, "rebuild" => 14.0, "produce" => 21.0, "transfer" => 21.0 }
    total = weights.sum do |stage, weight|
      stability = (states.find { |state| state.stage == stage }&.stability || 0).to_f
      weight * [ stability / stage_targets.fetch(stage), 1.0 ].min
    end
    total / weights.values.sum
  end

  def weakest_axis(target, events)
    rows = events.select { |event| event.target == target }
    return nil unless rows.any? { |event| Array(event.response.to_h["_exposed_axes"]).any? }

    AXES.max_by do |axis|
      wrong = rows.count { |event| event.trap_axis == axis && !event.correct? }
      exposure = rows.count { |event| Array(event.response.to_h["_exposed_axes"]).include?(axis) }
      exposure.zero? ? 0.0 : wrong.fdiv(exposure)
    end
  end

  def accuracy_by_axis(events)
    AXES.each_with_object({}) do |axis, result|
      wrong = events.count { |event| event.trap_axis == axis && !event.correct? }
      exposed = events.count { |event| Array(event.response.to_h["_exposed_axes"]).include?(axis) }
      result[axis] = { "wrong" => wrong, "exposed" => exposed, "error_rate" => ratio(wrong, exposed) }
    end
  end

  def top_confusions(events)
    pairs = Hash.new(0)
    events.each do |event|
      next unless event.trap_axis
      response = event.response.to_h
      selected = response.reject { |key, _| key.to_s.start_with?("_") }.values.flatten.first.to_s.strip
      next if selected.blank?

      pairs[[ event.trap_axis, selected ]] += 1
    end
    pairs.sort_by { |(_axis, _selected), count| -count }.first(8).map do |(axis, selected), count|
      { "axis" => axis, "selected" => selected, "count" => count }
    end
  end

  def retention(states, events, now:)
    predicted = states.filter_map do |state|
      next 0.0 if state.stability.to_f <= 0.0

      elapsed = state.last_reviewed_at ? (now.to_f - state.last_reviewed_at.to_f) / 86_400.0 : 0.0
      EnglishArcade::Scheduler.retrievability(stability: state.stability, elapsed_days: [ elapsed, 0.0 ].max)
    end
    {
      "predicted_now" => predicted.empty? ? 0.0 : (predicted.sum / predicted.length).round(4),
      "observed_7d" => observed_retention(events, minimum_interval_days: 7),
      "observed_30d" => observed_retention(events, minimum_interval_days: 30),
      "delayed_variant_pass_rate" => observed_retention(
        events.select { |event| event.stage == "transfer" && event.response.to_h["_variant"] == "delayed_variant" },
        minimum_interval_days: 0
      )
    }
  end

  def observed_retention(events, minimum_interval_days:)
    sample = events.select { |event| event.actual_interval_days.to_f >= minimum_interval_days.to_f }
    ratio(sample.count(&:correct?), sample.length)
  end

  def response_times(events)
    STAGES.each_with_object({}) do |stage, result|
      values = events.select { |event| event.stage == stage && event.response_ms.to_i.positive? }.map(&:response_ms).sort
      result[stage] = values.empty? ? { "median_ms" => nil, "count" => 0 } : { "median_ms" => median(values), "count" => values.length }
    end
  end

  def stage_accuracy(events)
    (STAGES - [ "meet" ]).each_with_object({}) do |stage, result|
      rows = events.select { |event| event.stage == stage }
      result[stage] = { "correct" => rows.count(&:correct?), "total" => rows.length, "accuracy" => ratio(rows.count(&:correct?), rows.length) }
    end
  end

  def minutes_today(lessons, now:)
    lessons.select { |lesson| lesson.started_at&.to_date == now.to_date }.sum do |lesson|
      duration = lesson.duration_ms.to_f
      duration.positive? ? duration / 60_000.0 : 0.0
    end.round(1)
  end

  def recent_lapses(events)
    events.select { |event| !event.correct? }.sort_by(&:answered_at).reverse.first(10).map do |event|
      { "card_key" => event.card_key, "stage" => event.stage, "axis" => event.trap_axis, "answered_at" => event.answered_at&.iso8601 }
    end
  end

  def ratio(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator.to_f).round(4)
  end

  def median(values)
    middle = values.length / 2
    values.length.odd? ? values[middle] : ((values[middle - 1] + values[middle]) / 2.0).round
  end
end

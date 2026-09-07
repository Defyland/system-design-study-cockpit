# frozen_string_literal: true

require_relative "arcade_content"
require_relative "arcade_lesson_composer"
require_relative "../../lib/english_arcade/exercise_grader"
require_relative "../../lib/english_arcade/scheduler"

class ArcadeLessonRecorder
  class InvalidResult < StandardError
    attr_reader :code

    def initialize(code = "invalid_result")
      @code = code
      super(code)
    end
  end

  class StaleContent < InvalidResult
    def initialize
      super("stale_content")
    end
  end

  class Finished < InvalidResult
    def initialize
      super("lesson_finished")
    end
  end

  class Tampered < InvalidResult
    def initialize
      super("invalid_exercise")
    end
  end

  STAGES = ArcadeLessonComposer::STAGES
  LADDER = %w[meet recognize trap cloze rebuild produce speak transfer].freeze
  MECHANICAL_AXES = %w[order].freeze
  STAGE_TARGETS = { "recognize" => 7.0, "trap" => 7.0, "cloze" => 14.0, "rebuild" => 14.0, "produce" => 21.0, "transfer" => 21.0 }.freeze

  def initialize(learner_key: "anonymous", content: nil, clock: -> { Time.current })
    @learner_key = learner_key.to_s.presence || "anonymous"
    @content = content || ArcadeContent.new
    @clock = clock
  end

  def call(lesson:, result:)
    lesson = owned_lesson(lesson)
    payload = stringify(result || {})
    exercise_id = payload["exercise_id"].to_s.strip
    raise Tampered if exercise_id.blank? || exercise_id.bytesize > 512

    lesson.with_lock do
      plan = Array(lesson.plan).map { |entry| stringify(entry) }
      entry = plan.find { |candidate| candidate["exercise_id"].to_s == exercise_id }
      raise StaleContent unless entry

      attempt_no = entry.fetch("attempt_no", 1).to_i
      existing = lesson.arcade_exercise_events.find_by(exercise_id: exercise_id, attempt_no: attempt_no)
      return stored_result(existing, lesson: lesson, entry: entry) if existing
      raise Finished unless lesson.active?

      next_position = lesson.summary.to_h.fetch("next_position", 0).to_i
      raise Tampered unless entry.fetch("position", -1).to_i == next_position

      item = @content.item_by_key(entry.fetch("card_key"))
      raise StaleContent unless item

      exercise = materialize_and_verify(item, entry)
      response = bounded_response(payload["response"])
      response_text = bounded_text(payload["response_text"])
      response_ms = bounded_response_ms(payload["response_ms"])
      self_rating = bounded_rating(payload["self_rating"])
      grade = EnglishArcade::ExerciseGrader.new(exercise, item: item).grade(
        response: response,
        response_text: response_text,
        response_ms: response_ms,
        self_rating: self_rating
      )
      now = @clock.call
      state_before, state_after = transition_state(
        item: item,
        stage: entry.fetch("stage"),
        rating: grade.fetch("rating"),
        attempt_no: attempt_no,
        now: now,
        seed: "#{lesson.seed}:#{exercise_id}",
        boss: entry["boss"] == true
      )
      propagate_lapse!(item: item, stage: entry.fetch("stage"), now: now) if grade.fetch("rating").to_i == 1 && entry["boss"] != true
      reveal = @content.reveal(
        item,
        exercise: exercise,
        grade: grade,
        response: response,
        response_text: response_text
      )
      event_response = response.is_a?(Hash) ? response.dup : { "value" => response }
      event_response["_reveal"] = reveal
      event_response["_exposed_axes"] = exposed_axes(item, exercise)
      variant = exercise.dig("payload", "variant").to_s.strip
      event_response["_variant"] = variant unless variant.empty?
      event_response["_mechanical_axis"] = "order" if grade.fetch("trap_axis", nil).to_s == "order"
      event = lesson.arcade_exercise_events.create!(
        learner_key: @learner_key,
        target: item.fetch(:target).to_s,
        card_key: item.fetch(:key).to_s,
        stage: entry.fetch("stage").to_s,
        exercise_type: entry.fetch("type").to_s,
        exercise_id: exercise_id,
        position: entry.fetch("position").to_i,
        attempt_no: attempt_no,
        boss_round: entry["boss"] == true,
        reason: entry["reason"].to_s.presence,
        correct: grade.fetch("correct") == true,
        rating: grade.fetch("rating").to_i.clamp(1, 4),
        self_rating: self_rating,
        trap_axis: persist_axis(grade.fetch("trap_axis", nil)),
        response_ms: response_ms,
        response: event_response,
        response_text: response_text,
        similarity: grade.dig("details", "similarity"),
        anchors_hit: grade.dig("details", "anchors_hit"),
        anchors_total: grade.dig("details", "anchors_total"),
        stability_before: state_before.fetch("stability"),
        stability_after: state_after.fetch("stability"),
        scheduled_interval_days: state_after.fetch("scheduled_interval_days"),
        actual_interval_days: actual_interval(state_before, now),
        retrievability: state_after.fetch("retrievability"),
        answered_at: now,
        content_version: @content.content_version(item).to_s
      )
      unlocks = entry["boss"] == true ? [] : unlock_next_stage(item: item, stage: entry.fetch("stage"), grade: grade, now: now)
      requeue = enqueue_relearn!(lesson: lesson, entry: entry, grade: grade, plan: plan, now: now)
      update_lesson_counters!(lesson, plan: plan, now: now)
      lesson.update!(plan: plan, summary: lesson.summary.to_h.merge("next_position" => entry.fetch("position").to_i + 1))

      result_payload(event, lesson: lesson, entry: entry, reveal: reveal, state_before: state_before, state_after: state_after, unlocks: unlocks, requeue: requeue)
    rescue ActiveRecord::RecordNotUnique
      duplicate = lesson.arcade_exercise_events.find_by(exercise_id: exercise_id, attempt_no: attempt_no)
      return stored_result(duplicate, lesson: lesson, entry: entry) if duplicate

      raise
    end
  end

  alias record call

  def finish(lesson:, duration_ms: nil)
    lesson = owned_lesson(lesson)
    lesson.with_lock do
      return finish_payload(lesson, persisted_finish_summary(lesson)) if lesson.finished?
      raise Finished unless lesson.active?

      events = lesson.arcade_exercise_events.to_a
      plan_size = Array(lesson.plan).length
      next_position = lesson.summary.to_h.fetch("next_position", 0).to_i
      raise InvalidResult, "lesson_incomplete" unless plan_size.positive? && next_position >= plan_size && events.length >= plan_size

      scored = scored_events(events)
      summary = finish_summary(lesson, events)
      lesson.update!(
        status: :finished,
        finished_at: @clock.call,
        duration_ms: bounded_ms(duration_ms),
        exercises_done: events.length,
        correct_count: events.count(&:correct?),
        accuracy: ratio(scored.count(&:correct?), scored.length),
        boss_correct: events.count { |event| event.boss_round? && event.correct? },
        boss_total: events.count(&:boss_round?),
        summary: lesson.summary.to_h.merge(summary)
      )
      lesson.reload
      finish_payload(lesson, summary)
    end
  end

  private

  def owned_lesson(lesson)
    record = lesson.is_a?(ArcadeLesson) ? lesson : ArcadeLesson.find_by(id: lesson)
    raise InvalidResult, "lesson_not_found" unless record && record.learner_key.to_s == @learner_key

    record
  end

  def materialize_and_verify(item, entry)
    exercise = @content.build(
      item,
      stage: entry.fetch("stage"),
      slot: entry.fetch("slot", 0).to_i,
      timed: entry["boss"] == true,
      boss: entry["boss"] == true,
      occurrence: entry["boss"] == true ? entry.fetch("boss_index", entry.fetch("slot", 0)).to_i : nil
    )
    expected = entry["factory_exercise_id"].to_s.presence || exercise.fetch("exercise_id")
    raise StaleContent unless expected == exercise.fetch("exercise_id")

    exercise
  rescue ArgumentError, KeyError
    raise StaleContent
  end

  def transition_state(item:, stage:, rating:, attempt_no:, now:, seed:, boss: false)
    key = {
      learner_key: @learner_key,
      target: item.fetch(:target).to_s,
      card_key: item.fetch(:key).to_s,
      stage: stage.to_s
    }
    attempts = 0
    begin
      attempts += 1
      ArcadeStageState.transaction(requires_new: true) do
        # A new row cannot be locked with `with_lock`. Lock an existing row
        # before reading it; the unique identity index and one retry protect
        # concurrent first reviews of the same (learner, card, stage).
        state = ArcadeStageState.lock.find_by(key) || ArcadeStageState.new(key)
        state.due_at ||= now
        state.stability ||= 0
        state.difficulty ||= 5
        state.reps ||= 0
        state.lapses ||= 0
        state.streak ||= 0
        state.content_version = @content.content_version(item).to_s
        before = state.attributes.slice("stability", "difficulty", "due_at", "lapses", "reps", "streak", "last_rating", "last_result", "last_reviewed_at")
        transition = EnglishArcade::Scheduler.review(
          state: {
            "card_key" => state.card_key,
            "stability" => state.stability,
            "difficulty" => state.difficulty,
            "status" => state.status,
            "due_at" => state.due_at,
            "lapses" => state.lapses,
            "last_reviewed_at" => state.last_reviewed_at
          },
          rating: rating,
          stage: stage,
          reviewed_at: now,
          attempt_no: attempt_no,
          seed: seed,
          boss: boss
        )

        if boss
          # Rain is measurement-only. A miss can pull an existing review due
          # now, but it never grows S, reps, streak, lapses, or last-review
          # metadata. An unseen card remains ephemeral until the ladder sees it.
          if state.persisted? && rating.to_i == 1
            state.update_columns(due_at: now, updated_at: now)
          end
          after = transition.merge(
            "stability" => state.stability.to_f,
            "difficulty" => state.difficulty.to_f,
            "status" => state.status,
            "lapses" => state.lapses.to_i,
            "due_at" => state.persisted? && rating.to_i == 1 ? now : state.due_at,
            "last_result" => state.last_result,
            "last_reviewed_at" => state.last_reviewed_at,
            "reps" => state.reps.to_i,
            "streak" => state.streak.to_i
          )
          [ before, after ]
        else
          state.stability = transition.fetch("stability")
          state.difficulty = transition.fetch("difficulty")
          state.status = transition.fetch("status")
          state.due_at = transition.fetch("due_at")
          state.lapses = transition.fetch("lapses")
          state.reps = state.reps.to_i + 1
          state.streak = rating.to_i >= 3 ? state.streak.to_i + 1 : 0
          state.last_rating = rating
          state.last_result = transition.fetch("last_result").to_s.in?(%w[success boss_pass])
          state.last_reviewed_at = transition.fetch("last_reviewed_at")
          state.metadata = state.metadata.to_h.merge(
            "retrievability" => transition.fetch("retrievability"),
            "scheduled_interval_days" => transition.fetch("scheduled_interval_days")
          )
          state.save!
          [ before, transition.merge("reps" => state.reps, "streak" => state.streak) ]
        end
      end
    rescue ActiveRecord::RecordNotUnique
      raise if attempts >= 2

      retry
    end
  end

  def unlock_next_stage(item:, stage:, grade:, now:)
    # Role rehearsal has its own explicit Produce/Transfer sequence.
    return [] if @content.interview_item?(item)
    return [] unless grade.fetch("rating").to_i >= 3
    return [] unless STAGES.include?(stage.to_s)

    current_index = LADDER.index(stage.to_s)
    return [] unless current_index

    next_stage = LADDER[current_index + 1]
    return [] if next_stage.blank?
    return [] unless @content.supported?(item, stage: next_stage, slot: 0)
    return [] if next_stage == "produce" && !passed_stages?(item, %w[cloze rebuild])
    return [] if next_stage == "transfer" && !passed_stages?(item, [ "produce" ], minimum_stability: 2.0)

    unlock_state!(item: item, stage: next_stage, now: now)
    unlocked = [ next_stage ]
    if stage.to_s == "produce"
      # Speaking is an optional satellite: a strong Produce pass must also
      # open Transfer so learners are never forced through microphone work.
      if passed_stages?(item, [ "produce" ], minimum_stability: 2.0) && @content.supported?(item, stage: "transfer", slot: 0)
        unlock_state!(item: item, stage: "transfer", now: now)
        unlocked << "transfer"
      end

      %w[compress feynman].each do |satellite|
        next unless @content.supported?(item, stage: satellite, slot: 0)

        unlock_state!(item: item, stage: satellite, now: now)
        unlocked << satellite
      end
    end
    unlocked
  end

  def unlock_state!(item:, stage:, now:)
    key = {
      learner_key: @learner_key,
      target: item.fetch(:target).to_s,
      card_key: item.fetch(:key).to_s,
      stage: stage.to_s
    }
    attempts = 0
    begin
      attempts += 1
      ArcadeStageState.transaction(requires_new: true) do
        state = ArcadeStageState.lock.find_by(key) || ArcadeStageState.new(key)
        state.assign_attributes(
          status: state.status.to_s == "review" ? state.status : "new",
          due_at: [ state.due_at || now, now ].min,
          content_version: @content.content_version(item).to_s
        )
        state.save!
      end
    rescue ActiveRecord::RecordNotUnique
      raise if attempts >= 2

      retry
    end
  end

  def propagate_lapse!(item:, stage:, now:)
    index = LADDER.index(stage.to_s)
    return if index.nil? || index < LADDER.index("cloze")

    prior_stage = LADDER[index - 1]
    state = ArcadeStageState.lock.find_by(
      learner_key: @learner_key,
      target: item.fetch(:target).to_s,
      card_key: item.fetch(:key).to_s,
      stage: prior_stage
    )
    return unless state

    due_limit = now + 1.day
    state.update!(
      stability: state.stability.to_f * 0.7,
      due_at: [ state.due_at || due_limit, due_limit ].min
    )
  end

  def passed_stages?(item, stages, minimum_stability: 0.0)
    stages.all? do |stage|
      state = ArcadeStageState.find_by(
        learner_key: @learner_key,
        target: item.fetch(:target).to_s,
        card_key: item.fetch(:key).to_s,
        stage: stage
      )
      state && state.stability.to_f >= minimum_stability && state.last_result != false
    end
  end

  def enqueue_relearn!(lesson:, entry:, grade:, plan:, now:)
    return nil if grade.fetch("correct") == true || entry["boss"] == true
    return nil if plan.any? { |candidate| candidate["reason"] == "relearn" && candidate["factory_exercise_id"] == entry["factory_exercise_id"] }

    next_attempt = entry.fetch("attempt_no", 1).to_i + 1
    insertion = [ entry.fetch("position").to_i + 3, plan.length ].min
    requeue_entry = relearn_entry(entry, attempt_no: next_attempt, position: insertion)
    reencode_entry = nil
    if entry["stage"].to_s == "produce"
      item = @content.item_by_key(entry.fetch("card_key"))
      if item && !@content.interview_item?(item) && @content.supported?(item, stage: "cloze", slot: entry.fetch("slot", 0).to_i)
        cloze = @content.build(item, stage: "cloze", slot: entry.fetch("slot", 0).to_i)
        reencode_entry = entry.merge(
          "exercise_id" => "#{cloze.fetch("exercise_id")}:reencode:#{next_attempt}",
          "factory_exercise_id" => cloze.fetch("exercise_id"),
          "stage" => "cloze",
          "type" => "cloze",
          "reason" => "relearn",
          "attempt_no" => next_attempt,
          "position" => insertion,
          "boss" => false,
          "boss_index" => nil
        )
        plan.insert(insertion, reencode_entry)
        requeue_entry["position"] = insertion + 1
      end
    end
    plan.insert(requeue_entry.fetch("position"), requeue_entry)
    renumber_positions!(plan)
    result = { "exercise_id" => requeue_entry.fetch("exercise_id"), "position" => requeue_entry.fetch("position") }
    result["reencode"] = { "exercise_id" => reencode_entry.fetch("exercise_id"), "position" => reencode_entry.fetch("position") } if reencode_entry
    result
  end

  def relearn_entry(entry, attempt_no:, position:)
    entry.merge(
      "exercise_id" => "#{entry.fetch("factory_exercise_id")}:relearn:#{attempt_no}",
      "reason" => "relearn",
      "attempt_no" => attempt_no,
      "position" => position,
      "boss" => false,
      "boss_index" => nil
    )
  end

  def renumber_positions!(plan)
    plan.each_with_index { |entry, index| entry["position"] = index }
  end

  def update_lesson_counters!(lesson, plan:, now:)
    events = lesson.arcade_exercise_events.reload.to_a
    scored = scored_events(events)
    lesson.assign_attributes(
      exercises_total: plan.length,
      exercises_done: events.length,
      correct_count: events.count(&:correct?),
      accuracy: ratio(scored.count(&:correct?), scored.length),
      new_cards_count: lesson.new_cards_count.to_i,
      review_count: lesson.review_count.to_i,
      boss_correct: events.count { |event| event.boss_round? && event.correct? },
      boss_total: events.count(&:boss_round?)
    )
    lesson.save!
  end

  def result_payload(event, lesson:, entry:, reveal:, state_before:, state_after:, unlocks:, requeue:)
    {
      "correct" => event.correct?,
      "rating" => event.rating,
      "trap_axis" => event.trap_axis,
      "reveal" => reveal,
      "srs" => {
        "stage" => event.stage,
        "status" => state_after.fetch("status"),
        "stability_before" => state_before.fetch("stability").to_f,
        "stability_after" => state_after.fetch("stability").to_f,
        "due_at" => state_after.fetch("due_at")&.iso8601,
        "mastery" => mastery_for(event.card_key)
      },
      "unlocked" => unlocks,
      "requeue" => requeue,
      "lesson" => { "done" => lesson.exercises_done, "total" => lesson.exercises_total, "next_position" => lesson.summary.to_h.fetch("next_position", 0).to_i }
    }
  end

  def stored_result(event, lesson:, entry:)
    raise StaleContent unless event

    response = event.response.to_h
    reveal = response.delete("_reveal") || {}
    {
      "correct" => event.correct?,
      "rating" => event.rating,
      "trap_axis" => event.trap_axis,
      "reveal" => reveal,
      "srs" => {
        "stage" => event.stage,
        "status" => ArcadeStageState.find_by(learner_key: @learner_key, card_key: event.card_key, stage: event.stage)&.status,
        "stability_before" => event.stability_before.to_f,
        "stability_after" => event.stability_after.to_f,
        "due_at" => ArcadeStageState.find_by(learner_key: @learner_key, card_key: event.card_key, stage: event.stage)&.due_at&.iso8601,
        "mastery" => mastery_for(event.card_key)
      },
      "requeue" => nil,
      "lesson" => { "done" => lesson.exercises_done, "total" => lesson.exercises_total, "next_position" => lesson.summary.to_h.fetch("next_position", 0).to_i },
      "_idempotent" => true
    }
  end

  def finish_summary(lesson, events)
    axes = events.reject(&:correct?).filter_map(&:trap_axis).tally
    states_by_card = ArcadeStageState.where(
      learner_key: @learner_key,
      card_key: events.map(&:card_key).uniq
    ).to_a.group_by(&:card_key)
    cards = events.group_by(&:card_key).map do |card_key, rows|
      states = states_by_card.fetch(card_key, [])
      {
        "card_key" => card_key,
        "correct" => rows.count(&:correct?),
        "attempts" => rows.length,
        "next_due" => states.filter_map(&:due_at).min&.iso8601,
        "mastery" => mastery_for(card_key, states: states)
      }
    end
    scored = scored_events(events)
    { "accuracy" => ratio(scored.count(&:correct?), scored.length), "by_axis" => axes, "cards" => cards }
  end

  def scored_events(events)
    events.reject { |event| event.boss_round? || event.stage == "meet" }
  end

  def finish_payload(lesson, summary)
    {
      "accuracy" => lesson.accuracy.to_f,
      "max_combo" => max_combo(lesson.arcade_exercise_events.to_a),
      "misses_by_axis" => summary.fetch("by_axis", {}),
      "cards" => summary.fetch("cards", []),
      "summary" => summary,
      "perfect" => lesson.accuracy.to_f >= 1.0
    }
  end

  def persisted_finish_summary(lesson)
    lesson.summary.to_h.slice("accuracy", "by_axis", "cards")
  end

  def max_combo(events)
    current = 0
    events.sort_by(&:position).each_with_object([ 0 ]) do |event, result|
      current = event.correct? ? current + 1 : 0
      result[0] = [ result[0], current ].max
    end.first
  end

  def mastery_for(card_key, states: nil)
    states = states || ArcadeStageState.where(learner_key: @learner_key, card_key: card_key).to_a
    states = states.index_by(&:stage)
    weights = { "recognize" => 1.0, "trap" => 1.0, "cloze" => 2.0, "rebuild" => 2.0, "produce" => 3.0, "transfer" => 3.0 }
    weights = weights.slice(*ArcadeContent::INTERVIEW_PRACTICE_STAGES) if @content.interview_item?(@content.item_by_key(card_key))
    total = weights.sum do |stage, weight|
      stability = (states[stage]&.stability || 0).to_f
      weight * [ stability / STAGE_TARGETS.fetch(stage), 1.0 ].min
    end
    maximum = weights.values.sum
    produce_stability = (states["produce"]&.stability || 0).to_f
    transfer_stability = (states["transfer"]&.stability || 0).to_f
    { "score" => maximum.zero? ? 0.0 : (total / maximum).round(4), "mastered" => produce_stability >= 21 && transfer_stability >= 21 }
  end

  def persist_axis(axis)
    axis = axis.to_s.presence
    return nil if axis.blank? || MECHANICAL_AXES.include?(axis)

    ArcadeExerciseEvent::AXES.include?(axis) ? axis : "content"
  end

  def exposed_axes(item, exercise)
    case exercise.fetch("type")
    when "choose_best"
      Array(item[:distractors] || item["distractors"]).filter_map do |choice|
        (choice[:trap] || choice["trap"]).to_s.presence
      end.uniq.select { |axis| ArcadeExerciseEvent::AXES.include?(axis) }
    when "transfer"
      [ "content" ]
    when "trap_axis"
      Array(exercise.dig("payload", "axes")).map(&:to_s).select { |axis| ArcadeExerciseEvent::AXES.include?(axis) }.uniq
    when "cloze"
      Array(exercise.dig("payload", "blanks")).filter_map { |blank| blank["axis"].to_s.presence }.uniq
    else
      []
    end
  end

  def actual_interval(state_before, now)
    reviewed_at = state_before.to_h["last_reviewed_at"]
    return 0.0 unless reviewed_at.respond_to?(:to_f)

    [ (now.to_f - reviewed_at.to_f) / 86_400.0, 0.0 ].max.round(4)
  end

  def ratio(numerator, denominator)
    return 0.0 if denominator.to_i.zero?

    (numerator.to_f / denominator.to_f).round(4)
  end

  def bounded_response(value)
    case value
    when Hash then stringify(value).slice(*stringify(value).keys.first(32))
    when Array then value.first(64).map { |entry| entry.to_s.byteslice(0, 512).to_s }
    else value.to_s.byteslice(0, 512).to_s
    end
  end

  def bounded_text(value)
    value.to_s.byteslice(0, 16_000).to_s.presence
  end

  def bounded_ms(value)
    number = Integer(value, exception: false)
    number&.clamp(0, 86_400_000)
  end

  def bounded_response_ms(value)
    number = Integer(value, exception: false)
    raise InvalidResult, "invalid_response_ms" unless number&.between?(1, 3_600_000)

    number
  end

  def bounded_rating(value)
    return nil if value.to_s.blank?

    number = Integer(value, exception: false)
    raise InvalidResult, "invalid_self_rating" unless number&.between?(1, 4)

    number
  end

  def stringify(value)
    case value
    when Hash then value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
    when Array then value.map { |nested| stringify(nested) }
    else value
    end
  end
end

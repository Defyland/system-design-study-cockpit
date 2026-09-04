# frozen_string_literal: true

require "digest"
require "securerandom"
require_relative "arcade_content"

class ArcadeLessonComposer
  class StaleContent < ArgumentError; end

  SIZE = 12
  MAX_NEW = 2
  MAX_UNLOCK = 3
  BOSS_MAX = 6
  MIN_CARD_DISTANCE = 3
  STAGES = ArcadeContent::CORE_STAGES.freeze
  STAGE_RANK = STAGES.each_with_index.to_h.freeze
  PRACTICE_STAGES = %w[recognize trap cloze rebuild produce transfer].freeze

  attr_reader :content, :clock

  def initialize(learner_key: "anonymous", content: nil, clock: -> { Time.current })
    @learner_key = learner_key.to_s.presence || "anonymous"
    @content = content || ArcadeContent.new
    @clock = clock
  end

  def call(target_mode: "mixed", target: nil, card_key: nil, size: SIZE, new_cards: MAX_NEW, seed: nil, boss_only: false)
    mode = normalize_mode(target_mode)
    target = normalize_target(target, mode)
    items = available_items(mode, target, card_key)
    raise ArgumentError, "invalid_target" if items.empty?

    size = [ [ size.to_i, 1 ].max, 30 ].min
    new_cards = [ [ new_cards.to_i, 0 ].max, MAX_NEW ].min
    seed = seed.to_s.presence || SecureRandom.hex(8)
    now = @clock.call
    entries, touched, counts = build_plan(
      items: items, mode: mode, target: target, size: size, new_cards: new_cards, seed: seed, now: now, boss_only: boss_only
    )
    raise ArgumentError, "empty_lesson" if entries.empty?

    lesson = nil
    ArcadeLesson.transaction do
      lesson = ArcadeLesson.create!(
        learner_key: @learner_key,
        target_mode: mode,
        target: target,
        targets: touched.map { |item| item.fetch(:target).to_s }.uniq,
        status: :active,
        seed: seed,
        plan: entries,
        started_at: now,
        exercises_total: entries.length,
        new_cards_count: counts.fetch(:new_cards),
        review_count: counts.fetch(:review_count),
        boss_total: entries.count { |entry| entry["boss"] }
      )
    end
    lesson
  end

  alias compose call

  def exercises_for(lesson, current_position: nil)
    Array(lesson.plan).each_with_index.map do |entry, index|
      materialize_entry(entry, include_model: current_position && index == current_position.to_i)
    end
  rescue ArgumentError, KeyError
    raise StaleContent, "stale_content"
  end

  def materialize_entry(entry, include_model: false)
    entry = stringify(entry)
    item = @content.item_by_key(entry.fetch("card_key"))
    raise ArgumentError, "stale_content" unless item

    exercise = @content.learner_exercise(
      item,
      stage: entry.fetch("stage"),
      slot: entry.fetch("slot", 0).to_i,
      timed: entry["boss"] == true,
      boss: entry["boss"] == true,
      occurrence: entry["boss"] == true ? entry.fetch("boss_index", entry.fetch("slot", 0)).to_i : nil,
      include_model: include_model
    )
    expected_factory_id = entry["factory_exercise_id"].to_s.presence || exercise.fetch("exercise_id")
    raise ArgumentError, "stale_content" unless expected_factory_id == exercise.fetch("exercise_id")

    exercise.merge(
      "exercise_id" => entry.fetch("exercise_id"),
      "position" => entry.fetch("position"),
      "attempt_no" => entry.fetch("attempt_no", 1),
      "reason" => entry["reason"],
      "boss" => entry["boss"] == true,
      # Keep the persisted plan type gradeable/server-owned while presenting
      # boss recognition as its timed Rain interaction in the browser.
      "type" => entry["boss"] == true ? "rain" : exercise.fetch("type")
    ).compact
  end

  private

  def normalize_mode(value)
    mode = value.to_s.downcase.strip
    return mode if ArcadeLesson::TARGET_MODES.include?(mode)

    "mixed"
  end

  def normalize_target(value, mode)
    return "mixed" if mode == "mixed"
    return "interview" if mode == "interview" && value.to_s.blank?

    normalized = @content.normalize_target(value)
    normalized = "interview" if mode == "interview"
    normalized = value.to_s if mode == "card" && value.to_s.present?
    normalized.presence || "mixed"
  end

  def available_items(mode, target, card_key)
    items = if mode == "mixed"
      @content.items_for("mixed")
    elsif mode == "interview"
      @content.items_for("interview")
    else
      @content.items_for(target)
    end
    return items if mode != "card" || card_key.to_s.blank?

    items.select { |item| item.fetch(:key).to_s == card_key.to_s }
  end

  def build_plan(items:, mode:, target:, size:, new_cards:, seed:, now:, boss_only: false)
    state_scope = ArcadeStageState.where(learner_key: @learner_key)
    states = state_scope.to_a.group_by(&:card_key)
    due_items = items.select do |item|
      Array(states[item.fetch(:key).to_s]).any? { |state| state.due?(now) }
    end.sort_by do |item|
      state = Array(states[item.fetch(:key).to_s]).select { |candidate| candidate.due?(now) }.min_by(&:due_at)
      [ state&.due_at || now, -STAGE_RANK.fetch(state&.stage.to_s, 0), item.fetch(:key).to_s ]
    end
    fresh_items = round_robin(items.reject { |item| states.key?(item.fetch(:key).to_s) }, seed: seed).first(new_cards)
    touched = (fresh_items + due_items + items).uniq { |item| item.fetch(:key).to_s }
    touched = round_robin(touched, seed: seed)

    entries = []
    if boss_only
      touched = (due_items + items).uniq { |item| item.fetch(:key).to_s }.first(BOSS_MAX)
      touched.each_with_index do |item, index|
        entries << entry_for(item, stage: "recognize", reason: "boss", position: entries.length, attempt_no: 1, slot: index, seed: seed, boss: true, boss_index: index)
      end
      return [ entries, touched, { new_cards: 0, review_count: due_items.first(BOSS_MAX).length } ]
    end

    fresh_items.each do |item|
      break if entries.length >= size

      entry = entry_for(item, stage: "meet", reason: "new", position: entries.length, attempt_no: 1, slot: 0, seed: seed)
      entries << entry if entry
      break if entries.length >= size

      entry = entry_for(item, stage: "recognize", reason: "new", position: entries.length, attempt_no: 1, slot: 0, seed: seed)
      entries << entry if entry
    end

    # Only schedule a stage that already exists as an unlocked/due state.
    # Fresh cards have Meet + Recognize above; they must earn later rungs from
    # the recorder instead of being placed directly into Produce/Transfer.
    candidates = round_robin(
      touched.select { |item| Array(states[item.fetch(:key).to_s]).any? },
      seed: seed
    )
    candidates.each do |item|
      break if entries.length >= size

      stage = next_stage(item, states: states, now: now)
      next unless stage

      reason = due_items.include?(item) ? "due" : "practice"
      slot = stage_slot(stage, states: Array(states[item.fetch(:key).to_s]))
      entry = entry_for(item, stage: stage, reason: reason, position: entries.length, attempt_no: 1, slot: slot, seed: seed)
      entries << entry if entry
    end

    touched = entries.map { |entry| items.find { |item| item.fetch(:key).to_s == entry.fetch("card_key") } }.compact.uniq { |item| item.fetch(:key).to_s }
    boss_cards = touched.first(BOSS_MAX)
    boss_cards.each_with_index do |item, index|
      break if entries.length >= size + BOSS_MAX

      entry = entry_for(
        item,
        stage: "recognize",
        reason: "boss",
        position: entries.length,
        attempt_no: 1,
        slot: index + 1,
        seed: seed,
        boss: true,
        boss_index: index
      )
      entries << entry if entry
    end

    [ entries, touched, { new_cards: fresh_items.length, review_count: entries.count { |entry| entry["reason"] == "due" } } ]
  end

  def next_stage(item, states:, now:)
    card_states = Array(states[item.fetch(:key).to_s])
    due = card_states.select { |state| state.due_at && state.due_at <= now }
      .sort_by { |state| -STAGE_RANK.fetch(state.stage, 0) }
      .find { |state| @content.supported?(item, stage: state.stage, slot: stage_slot(state.stage, states: card_states)) }
    return due.stage if due

    card_states.select { |state| state.status.to_s == "new" }
      .sort_by { |state| -STAGE_RANK.fetch(state.stage, 0) }
      .find { |state| @content.supported?(item, stage: state.stage, slot: stage_slot(state.stage, states: card_states)) }&.stage
  end

  def stage_slot(stage, states:)
    if stage.to_s == "trap"
      trap = Array(states).find { |state| state.stage.to_s == "trap" }
      return trap&.reps.to_i
    end
    return 0 unless stage.to_s == "transfer"

    transfer = Array(states).find { |state| state.stage.to_s == "transfer" }
    transfer && transfer.stability.to_f >= 3.0 ? 1 : 0
  end

  def entry_for(item, stage:, reason:, position:, attempt_no:, slot:, seed:, boss: false, boss_index: nil)
    return nil unless @content.supported?(item, stage: stage, slot: slot)

    exercise = @content.build(
      item,
      stage: stage,
      slot: slot,
      timed: boss,
      boss: boss,
      occurrence: boss ? boss_index : nil
    )
    factory_id = exercise.fetch("exercise_id")
    identity = if boss
      "#{factory_id}:boss:#{boss_index || slot}"
    elsif reason == "relearn"
      "#{factory_id}:relearn:#{attempt_no}"
    else
      factory_id
    end
    {
      "exercise_id" => identity,
      "factory_exercise_id" => factory_id,
      "card_key" => item.fetch(:key).to_s,
      "target" => item.fetch(:target).to_s,
      "stage" => stage.to_s,
      "type" => exercise.fetch("type").to_s,
      "slot" => slot.to_i,
      "position" => position.to_i,
      "reason" => reason.to_s,
      "attempt_no" => attempt_no.to_i,
      "boss" => boss,
      "boss_index" => boss_index
    }
  end

  def round_robin(items, seed:)
    groups = items.group_by { |item| item.fetch(:target).to_s }
    targets = groups.keys.sort_by { |target| Digest::SHA256.hexdigest("#{seed}:#{target}") }
    result = []
    loop do
      appended = false
      targets.each do |target|
        item = groups[target].shift
        next unless item

        result << item
        appended = true
      end
      break unless appended
    end
    result
  end

  def stringify(value)
    case value
    when Hash then value.each_with_object({}) { |(key, nested), result| result[key.to_s] = stringify(nested) }
    when Array then value.map { |nested| stringify(nested) }
    else value
    end
  end
end

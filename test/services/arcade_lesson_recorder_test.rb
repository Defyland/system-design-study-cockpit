# frozen_string_literal: true

require "test_helper"

class ArcadeLessonRecorderTest < ActiveSupport::TestCase
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
    @now = Time.utc(2026, 9, 4, 12)
    @learner_key = "arcade-recorder-test"
    @content = ArcadeContent.new
  end

  test "boss pass and miss are measurement-only, with a miss making an existing state due now" do
    item = supported_item("recognize")
    state = stage_state(item, "recognize", stability: 7, reps: 3, due_at: @now + 2.days)

    pass_lesson, pass_entry = lesson_for(item, stage: "recognize", boss: true, boss_index: 0)
    record(pass_lesson, pass_entry, response: correct_choice(item, pass_entry))

    state.reload
    assert_equal 7.0, state.stability.to_f
    assert_equal 3, state.reps
    assert_equal @now + 2.days, state.due_at

    miss_lesson, miss_entry = lesson_for(item, stage: "recognize", boss: true, boss_index: 1)
    record(miss_lesson, miss_entry, response: wrong_choice(item, miss_entry))

    state.reload
    assert_equal 7.0, state.stability.to_f
    assert_equal 3, state.reps
    assert_equal @now, state.due_at
  end

  test "a miss requeues three positions later and a produce miss inserts cloze before its retry" do
    item = supported_item("recognize")
    lesson, entry = lesson_for(item, stage: "recognize", fillers: 4)
    record(lesson, entry, response: wrong_choice(item, entry))

    relearn = lesson.reload.plan.find { |candidate| candidate["reason"] == "relearn" }
    assert_equal "recognize", relearn.fetch("stage")
    assert_equal 2, relearn.fetch("attempt_no")
    assert_equal 3, relearn.fetch("position")

    produce_item = supported_item("produce") { |candidate| @content.supported?(candidate, stage: "cloze", slot: 0) }
    produce_lesson, produce_entry = lesson_for(produce_item, stage: "produce", fillers: 5)
    record(produce_lesson, produce_entry, response_text: "", self_rating: 1)

    requeued = produce_lesson.reload.plan.select { |candidate| candidate["reason"] == "relearn" }.sort_by { |candidate| candidate.fetch("position") }
    assert_equal %w[cloze produce], requeued.map { |candidate| candidate.fetch("stage") }
    assert_equal [ 3, 4 ], requeued.map { |candidate| candidate.fetch("position") }
  end

  test "a strong produce unlocks transfer without a completed speak stage" do
    item = supported_item("produce") { |candidate| @content.supported?(candidate, stage: "transfer", slot: 0) }
    %w[cloze rebuild].each do |stage|
      stage_state(item, stage, stability: 14, reps: 1, due_at: @now + 1.day, last_result: true)
    end
    lesson, entry = lesson_for(item, stage: "produce")

    result = record(lesson, entry, response_text: item.fetch("best_answer"), self_rating: 4)

    assert_includes result.fetch("unlocked"), "transfer"
    transfer = ArcadeStageState.find_by!(learner_key: @learner_key, card_key: item.fetch(:key), stage: "transfer")
    speak = ArcadeStageState.find_by!(learner_key: @learner_key, card_key: item.fetch(:key), stage: "speak")
    assert_equal "new", transfer.status
    assert_equal "new", speak.status
    assert_nil speak.last_reviewed_at
  end

  test "ownership, out-of-order tampering, and idempotent finish keep the persisted lesson boundary" do
    item = supported_item("recognize")
    lesson, entry = lesson_for(item, stage: "recognize", fillers: 1)
    future = lesson.plan.fetch(1)

    error = assert_raises(ArcadeLessonRecorder::Tampered) do
      record(lesson, future, response: correct_choice(item, future))
    end
    assert_equal "invalid_exercise", error.code
    assert_equal 0, ArcadeExerciseEvent.count

    owner_error = assert_raises(ArcadeLessonRecorder::InvalidResult) do
      ArcadeLessonRecorder.new(learner_key: "another-learner", content: @content, clock: -> { @now }).call(
        lesson: lesson,
        result: { exercise_id: entry.fetch("exercise_id"), response: correct_choice(item, entry) }
      )
    end
    assert_equal "lesson_not_found", owner_error.code

    record(lesson, entry, response: correct_choice(item, entry))
    incomplete = assert_raises(ArcadeLessonRecorder::InvalidResult) do
      recorder.finish(lesson: lesson, duration_ms: 5_000)
    end
    assert_equal "lesson_incomplete", incomplete.code

    future_item = @content.item_by_key(future.fetch("card_key"))
    record(lesson, future, response: correct_choice(future_item, future))
    finished = recorder.finish(lesson: lesson, duration_ms: 5_000)
    assert_equal 1.0, finished.fetch("accuracy")
    assert_equal "finished", lesson.reload.status
    assert_equal finished, recorder.finish(lesson: lesson, duration_ms: 8_000)
    assert_equal true, record(lesson, future, response: correct_choice(future_item, future)).fetch("_idempotent")
  end

  test "meet acknowledgements do not inflate lesson accuracy" do
    item = supported_item("recognize")
    meet = entry_for(item, stage: "meet", position: 0, boss: false)
    recognize = entry_for(item, stage: "recognize", position: 1, boss: false)
    lesson = ArcadeLesson.create!(
      learner_key: @learner_key,
      target_mode: "single",
      target: item.fetch(:target),
      targets: [ item.fetch(:target) ],
      status: "active",
      seed: "accuracy-test",
      started_at: @now,
      exercises_total: 2,
      plan: [ meet, recognize ]
    )

    record(lesson, meet)
    record(lesson, recognize, response: wrong_choice(item, recognize))
    retry_entry = lesson.reload.plan.find { |entry| entry["reason"] == "relearn" }
    record(lesson, retry_entry, response: wrong_choice(item, retry_entry))
    result = recorder.finish(lesson: lesson, duration_ms: 2_000)

    assert_equal 0.0, result.fetch("accuracy")
    assert_equal false, result.fetch("perfect")
  end

  test "trap review slot rotates with repetitions" do
    item = supported_item("trap")
    state = stage_state(item, "trap", stability: 7, reps: 2, due_at: @now)
    composer = ArcadeLessonComposer.new(learner_key: @learner_key, content: @content, clock: -> { @now })

    first = composer.call(target_mode: "single", target: item.fetch(:target), size: 1, new_cards: 0, seed: "trap-rotation-a")
    assert_equal 2, first.plan.first.fetch("slot")

    state.update!(reps: 3)
    second = composer.call(target_mode: "single", target: item.fetch(:target), size: 1, new_cards: 0, seed: "trap-rotation-b")
    assert_equal 3, second.plan.first.fetch("slot")
  end

  test "response timing is required but cannot boost recognition rating" do
    item = supported_item("recognize")
    lesson, entry = lesson_for(item, stage: "recognize")

    error = assert_raises(ArcadeLessonRecorder::InvalidResult) do
      recorder.call(lesson: lesson, result: { exercise_id: entry.fetch("exercise_id"), response: correct_choice(item, entry) })
    end
    assert_equal "invalid_response_ms", error.code

    result = record(lesson, entry, response: correct_choice(item, entry))
    assert_equal 3, result.fetch("rating")
  end

  private

  def recorder
    @recorder ||= ArcadeLessonRecorder.new(learner_key: @learner_key, content: @content, clock: -> { @now })
  end

  def supported_item(stage, &predicate)
    predicate ||= ->(_item) { true }
    @content.items_for("dsa").find do |item|
      @content.supported?(item, stage: stage, slot: 0) && predicate.call(item)
    end || raise("missing supported #{stage} card")
  end

  def stage_state(item, stage, stability:, reps:, due_at:, last_result: true)
    ArcadeStageState.create!(
      learner_key: @learner_key,
      target: item.fetch(:target),
      card_key: item.fetch(:key),
      stage: stage,
      status: "review",
      stability: stability,
      difficulty: 5,
      due_at: due_at,
      reps: reps,
      streak: reps,
      last_result: last_result,
      last_reviewed_at: @now - 1.day,
      content_version: @content.content_version(item)
    )
  end

  def lesson_for(item, stage:, boss: false, boss_index: nil, fillers: 0)
    entries = []
    entries << entry_for(item, stage: stage, position: 0, boss: boss, boss_index: boss_index)
    fillers.times do |index|
      filler = @content.items_for("dsa").find { |candidate| candidate.fetch(:key) != item.fetch(:key) } || item
      entries << entry_for(filler, stage: "recognize", position: entries.length, boss: false, suffix: "filler-#{index}")
    end
    lesson = ArcadeLesson.create!(
      learner_key: @learner_key,
      target_mode: "single",
      target: item.fetch(:target),
      targets: [ item.fetch(:target) ],
      status: "active",
      seed: "recorder-test-seed",
      started_at: @now,
      exercises_total: entries.length,
      boss_total: boss ? 1 : 0,
      plan: entries
    )
    [ lesson, entries.first ]
  end

  def entry_for(item, stage:, position:, boss:, boss_index: nil, suffix: nil)
    slot = boss_index || 0
    exercise = @content.build(item, stage: stage, slot: slot, timed: boss, boss: boss, occurrence: boss ? boss_index : nil)
    factory_id = exercise.fetch("exercise_id")
    exercise_id = if boss
      "#{factory_id}:boss:#{boss_index}"
    elsif suffix
      "#{factory_id}:#{suffix}"
    else
      factory_id
    end
    {
      "exercise_id" => exercise_id,
      "factory_exercise_id" => factory_id,
      "card_key" => item.fetch(:key),
      "target" => item.fetch(:target),
      "stage" => stage,
      "type" => exercise.fetch("type"),
      "slot" => slot,
      "position" => position,
      "reason" => boss ? "boss" : "practice",
      "attempt_no" => 1,
      "boss" => boss,
      "boss_index" => boss_index
    }
  end

  def record(lesson, entry, response: nil, response_text: nil, self_rating: nil)
    recorder.call(
      lesson: lesson,
      result: {
        exercise_id: entry.fetch("exercise_id"),
        response: response,
        response_text: response_text,
        response_ms: 1_000,
        self_rating: self_rating
      }
    )
  end

  def correct_choice(item, entry)
    choice_for(item, entry, correct: true)
  end

  def wrong_choice(item, entry)
    choice_for(item, entry, correct: false)
  end

  def choice_for(item, entry, correct:)
    exercise = @content.build(
      item,
      stage: entry.fetch("stage"),
      slot: entry.fetch("slot"),
      timed: entry["boss"] == true,
      boss: entry["boss"] == true,
      occurrence: entry["boss"] == true ? entry.fetch("boss_index") : nil
    )
    option = exercise.fetch("payload").fetch("options").find do |candidate|
      matches_answer = candidate.fetch("text") == item.fetch("best_answer")
      matches_answer == correct
    end
    option.fetch("id")
  end
end

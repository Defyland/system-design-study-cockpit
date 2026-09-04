# frozen_string_literal: true

require "test_helper"

class ArcadeProgressDashboardTest < ActiveSupport::TestCase
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
    @now = Time.utc(2026, 9, 4, 12)
    @learner_key = "arcade-dashboard-test"
    @content = ArcadeContent.new
    @lesson = ArcadeLesson.create!(
      learner_key: @learner_key,
      target_mode: "single",
      target: "dsa",
      targets: [ "dsa" ],
      status: "active",
      seed: "dashboard-test",
      started_at: @now,
      exercises_total: 0
    )
  end

  test "calibration compares self-rating to recorded results and excludes non-scored stages" do
    event(correct: true, self_rating: 4)
    event(correct: false, self_rating: 4)
    event(correct: false, self_rating: 2)
    event(stage: "meet", exercise_type: "meet", correct: true, self_rating: 4)
    event(stage: "recognize", correct: false, self_rating: 1, boss_round: true, trap_axis: "grammar")

    calibration = dashboard.fetch("calibration_30d")

    assert_equal 3, calibration.fetch("rated_events")
    assert_equal({ "self_rating" => 4, "events" => 2, "correct" => 1, "accuracy" => 0.5 }, calibration.dig("by_rating", "4"))
    assert_equal({ "self_rating" => 2, "events" => 1, "correct" => 0, "accuracy" => 0.0 }, calibration.dig("by_rating", "2"))
    assert_equal 0, calibration.dig("by_rating", "1", "events")
  end

  test "top confusions uses the revealed selected wording and exposes a due drill card" do
    event(
      correct: false,
      trap_axis: "grammar",
      response: { "value" => "choice-2", "_reveal" => { "details" => { "selected" => "The wrong authored phrase" } } }
    )
    event(
      correct: false,
      trap_axis: "grammar",
      response: { "value" => "choice-2", "_reveal" => { "details" => { "selected" => "The wrong authored phrase" } } }
    )

    item = @content.items_for("dsa").first
    ArcadeStageState.create!(
      learner_key: @learner_key,
      target: "dsa",
      card_key: item.fetch(:key),
      stage: "recognize",
      status: "review",
      stability: 7,
      difficulty: 5,
      due_at: @now - 1.hour,
      reps: 1,
      lapses: 0,
      streak: 1,
      last_result: false,
      last_reviewed_at: @now - 1.day,
      content_version: @content.content_version(item)
    )

    progress = dashboard
    confusion = progress.fetch("top_confusions_30d").first

    assert_equal "grammar", confusion.fetch("axis")
    assert_equal "The wrong authored phrase", confusion.fetch("selected")
    assert_equal 2, confusion.fetch("count")
    assert_equal item.fetch(:key), progress.dig("mastery_by_target", "dsa", "drill_card_key")
  end

  test "dashboard calculation leaves the metric constants unchanged" do
    axes = ArcadeProgressDashboard::AXES.dup
    stages = ArcadeProgressDashboard::STAGES.dup

    dashboard

    assert_equal axes, ArcadeProgressDashboard::AXES
    assert_equal stages, ArcadeProgressDashboard::STAGES
  end

  test "skill map includes every card and only counts reviewed states toward its stage" do
    items = @content.items_for("dsa")
    reviewed = items.fetch(0)
    due_new = items.fetch(1)
    last_reviewed_only = items.fetch(2)
    fresh = items.fetch(3)

    stage_state(reviewed, "recognize", reps: 1, due_at: @now + 2.days)
    stage_state(reviewed, "cloze", reps: 1, due_at: @now + 3.days)
    stage_state(due_new, "recognize", reps: 0, due_at: @now)
    stage_state(last_reviewed_only, "recognize", reps: 0, due_at: @now + 2.days, last_reviewed_at: @now - 1.day)

    map = dashboard.fetch("skill_map")

    assert_equal EnglishArcade::Schema::CANONICAL_TARGETS.sort, map.keys.sort
    assert_equal 164, map.values.sum(&:length)
    reviewed_card = map.fetch("dsa").find { |card| card.fetch("card_key") == reviewed.fetch(:key) }
    due_new_card = map.fetch("dsa").find { |card| card.fetch("card_key") == due_new.fetch(:key) }
    new_card = map.fetch("dsa").find { |card| card.fetch("card_key") == fresh.fetch(:key) }
    review_card = map.fetch("dsa").find { |card| card.fetch("card_key") == last_reviewed_only.fetch(:key) }

    assert_equal "cloze", reviewed_card.fetch("highest_stage")
    assert_equal "review", reviewed_card.fetch("status")
    assert reviewed_card.fetch("title").present?
    assert reviewed_card.fetch("topic").present?
    assert_nil due_new_card.fetch("highest_stage")
    assert_equal "due", due_new_card.fetch("status")
    assert_nil new_card.fetch("highest_stage")
    assert_equal "new", new_card.fetch("status")
    assert_equal "recognize", review_card.fetch("highest_stage")
    assert_equal "review", review_card.fetch("status")
  end

  private

  def dashboard
    ArcadeProgressDashboard.new(learner_key: @learner_key, content: @content, clock: -> { @now }).call
  end

  def event(stage: "recognize", exercise_type: "choose_best", correct:, rating: 1, self_rating: nil, trap_axis: nil, boss_round: false, response: {})
    position = @lesson.arcade_exercise_events.count
    @lesson.arcade_exercise_events.create!(
      learner_key: @learner_key,
      target: "dsa",
      card_key: "dsa-01-pattern-naming",
      stage: stage,
      exercise_type: exercise_type,
      exercise_id: "dashboard-event-#{position}-#{stage}-#{boss_round}",
      position: position,
      attempt_no: 1,
      boss_round: boss_round,
      reason: "practice",
      correct: correct,
      rating: rating,
      self_rating: self_rating,
      trap_axis: trap_axis,
      response_ms: 1_000,
      response: response,
      answered_at: @now,
      content_version: "dashboard-test"
    )
  end

  def stage_state(item, stage, reps:, due_at:, last_reviewed_at: nil)
    ArcadeStageState.create!(
      learner_key: @learner_key,
      target: item.fetch(:target),
      card_key: item.fetch(:key),
      stage: stage,
      status: reps.positive? || last_reviewed_at ? "review" : "new",
      stability: reps.positive? ? 7 : 0,
      difficulty: 5,
      due_at: due_at,
      reps: reps,
      lapses: 0,
      streak: reps,
      last_result: reps.positive? || last_reviewed_at ? true : nil,
      last_reviewed_at: last_reviewed_at,
      content_version: @content.content_version(item)
    )
  end
end

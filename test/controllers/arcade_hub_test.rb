# frozen_string_literal: true

require "test_helper"

class ArcadeHubTest < ActionDispatch::IntegrationTest
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
  end

  test "hub renders calibration, recorded-confusion, and single-card drill surfaces" do
    get arena_path, headers: { "REMOTE_USER" => "arcade-hub-test" }

    assert_response :success
    assert_select "[data-arena-top-confusions] li", text: /No selections recorded for these axes yet\./
    assert_select "[data-arena-calibration]", text: /No self-rated answers yet\./
    assert_select "input[name='lesson[target_mode]'][value='card']", minimum: 1
    assert_select "input[name='lesson[card_key]']", minimum: 1
  end

  test "the card drill uses the existing lesson route and stays card-scoped" do
    item = ArcadeContent.new.items_for("dsa").first

    post arcade_lessons_path,
      params: { lesson: { target_mode: "card", target: "dsa", card_key: item.fetch(:key), size: 6, new_cards: 1 } },
      headers: { "REMOTE_USER" => "arcade-hub-test" }

    assert_response :see_other
    lesson = ArcadeLesson.order(:id).last
    assert_redirected_to arcade_lesson_path(lesson)
    assert_equal "card", lesson.target_mode
    assert_equal [ item.fetch(:key) ], lesson.plan.map { |entry| entry.fetch("card_key") }.uniq
  end

  test "hub resumes only the learner's latest active lesson without creating another" do
    composer = ArcadeLessonComposer.new(learner_key: "arcade-hub-test")
    previous = composer.call(seed: "previous")
    current = composer.call(seed: "current")
    previous.update!(updated_at: 1.hour.ago)
    finished = composer.call(seed: "finished")
    finished.complete!
    foreign = ArcadeLessonComposer.new(learner_key: "someone-else").call(seed: "foreign")

    assert_no_difference("ArcadeLesson.count") do
      get arena_path, headers: { "REMOTE_USER" => "arcade-hub-test" }
    end

    assert_response :success
    assert_select "a[href='#{arcade_lesson_path(current)}']", text: "Resume lesson"
    [ previous, finished, foreign ].each do |lesson|
      assert_select "a[href='#{arcade_lesson_path(lesson)}']", count: 0
    end

    current.complete!
    previous.complete!
    get arena_path, headers: { "REMOTE_USER" => "arcade-hub-test" }
    assert_select "[data-arena-resume]", count: 0
  end

  test "a reviewed card drill uses its highest supported stage even when not due" do
    content = ArcadeContent.new
    item = content.items_for("dsa").find { |candidate| content.supported?(candidate, stage: "cloze", slot: 0) }
    due_at = 2.days.from_now
    [ "recognize", "cloze" ].each do |stage|
      ArcadeStageState.create!(
        learner_key: "arcade-hub-test",
        target: item.fetch(:target),
        card_key: item.fetch(:key),
        stage: stage,
        status: "review",
        stability: 7,
        difficulty: 5,
        due_at: due_at,
        reps: 1,
        lapses: 0,
        streak: 1,
        last_result: true,
        last_reviewed_at: 1.day.ago,
        content_version: content.content_version(item)
      )
    end

    post arcade_lessons_path,
      params: { lesson: { target_mode: "card", target: "dsa", card_key: item.fetch(:key), size: 6, new_cards: 1 } },
      headers: { "REMOTE_USER" => "arcade-hub-test" }

    assert_response :see_other
    lesson = ArcadeLesson.order(:id).last
    assert_equal "cloze", lesson.plan.first.fetch("stage")
    assert_equal "practice", lesson.plan.first.fetch("reason")
    assert_equal due_at.to_i, ArcadeStageState.find_by!(learner_key: "arcade-hub-test", card_key: item.fetch(:key), stage: "cloze").due_at.to_i
  end
end

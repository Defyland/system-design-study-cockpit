require "test_helper"

class ArcadeLessonComposerTest < ActiveSupport::TestCase
  test "an editorial answer change invalidates an open lesson even when its schema version stays the same" do
    content = ArcadeContent.new
    composer = ArcadeLessonComposer.new(learner_key: "editorial-revision", content: content)
    lesson = composer.call(target_mode: "interview", interview_role: "frontend", size: 3, new_cards: 1, seed: "editorial")
    item = content.item_by_key(lesson.plan.first.fetch("card_key"))
    original_version = content.content_version(item)
    assert_equal original_version, content.content_version(item.to_a.reverse.to_h)
    assert_equal 3, composer.exercises_for(lesson, current_position: 0).length

    item[:best_answer] = item["best_answer"] = "I would revise this answer after checking the actual release boundary."
    refute_equal original_version, content.content_version(item)
    assert_raises(ArcadeLessonComposer::StaleContent) { composer.exercises_for(lesson, current_position: 0) }
    assert_no_difference "ArcadeExerciseEvent.count" do
      assert_raises(ArcadeLessonRecorder::StaleContent) do
        ArcadeLessonRecorder.new(learner_key: "editorial-revision", content: content).call(
          lesson: lesson,
          result: { exercise_id: lesson.plan.first.fetch("exercise_id"), response: { confirmed: true }, response_ms: 100 }
        )
      end
    end
  end

  test "an overdue review takes the last slot before an unlocked stage that is not due" do
    content = ArcadeContent.new
    now = Time.current
    learner = "review-priority"
    due_item = content.items_for("dsa").first
    practice_item = content.items_for("ruby").first
    assert practice_item, "Ruby practice content must be available"

    [ [ due_item, now - 2.days, "review" ], [ practice_item, now + 1.day, "new" ] ].each do |item, due_at, status|
      ArcadeStageState.create!(
        learner_key: learner, target: item.fetch(:target), card_key: item.fetch(:key),
        stage: "recognize", status: status, due_at: due_at,
        content_version: content.content_version(item)
      )
    end

    # Put the non-due target first in the mixed target rotation, so this
    # exercises review priority independently of the shuffle seed.
    seed = (1..100).map(&:to_s).find do |candidate|
      Digest::SHA256.hexdigest("#{candidate}:#{practice_item.fetch(:target)}") < Digest::SHA256.hexdigest("#{candidate}:#{due_item.fetch(:target)}")
    end
    assert seed
    lesson = ArcadeLessonComposer.new(learner_key: learner, content: content, clock: -> { now }).call(
      size: 1, new_cards: 0, seed: seed
    )

    assert_equal due_item.fetch(:key), lesson.plan.first.fetch("card_key")
    assert_equal "due", lesson.plan.first.fetch("reason")
    assert_equal 1, lesson.review_count
    assert_equal 0, lesson.new_cards_count
  end
end

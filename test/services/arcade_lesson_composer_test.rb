require "test_helper"

class ArcadeLessonComposerTest < ActiveSupport::TestCase
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

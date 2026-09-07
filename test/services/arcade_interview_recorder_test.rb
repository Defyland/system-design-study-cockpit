require "test_helper"

class ArcadeInterviewRecorderTest < ActiveSupport::TestCase
  setup do
    @learner = "role-recorder"
    @composer = ArcadeLessonComposer.new(learner_key: @learner)
    @recorder = ArcadeLessonRecorder.new(learner_key: @learner)
    @lesson = @composer.call(target_mode: "interview", interview_role: "frontend", size: 3, new_cards: 1)
    @item = ArcadeContent.new.item_by_key(@lesson.plan.first.fetch("card_key"))
  end

  test "successful interview rehearsal never unlocks the canonical ladder or satellites" do
    meet = record(0, response: { confirmed: true })
    production = record(1, response_text: @item.fetch("best_answer"), self_rating: 4)
    exercise = @composer.exercises_for(@lesson.reload, current_position: 2).fetch(2)
    choice = exercise.dig("payload", "options").find { |option| option.fetch("text") == @item.dig("follow_up", "best_answer") }
    transfer = record(2, response: choice.fetch("id"))
    [ meet, production, transfer ].each do |result|
      assert result.fetch("correct")
      assert_empty result.fetch("unlocked")
    end
    assert_equal %w[meet produce transfer], ArcadeStageState.where(learner_key: @learner).order(:stage).pluck(:stage)

    # Meeting a model is not a pending recall exercise; legacy unused rungs
    # must not remain in the hub's review count either.
    ArcadeStageState.where(learner_key: @learner, stage: "meet").update_all(due_at: 1.day.ago)
    assert_equal 0, ArcadeProgressDashboard.new(learner_key: @learner).call.dig("due", "total")
    ArcadeStageState.where(learner_key: @learner, stage: %w[produce transfer]).update_all(stability: 21)
    finished = @recorder.finish(lesson: @lesson, duration_ms: 3000)
    assert_equal 1.0, finished.fetch("cards").first.dig("mastery", "score")
  end

  test "a failed role production requeues typed recall without cloze reencoding" do
    record(0, response: { confirmed: true })
    result = record(1, response_text: "microfrontends", self_rating: 4)

    refute result.fetch("correct")
    assert_empty result.fetch("unlocked")
    assert result.fetch("requeue")
    refute result.fetch("requeue").key?("reencode")
    assert_equal %w[meet produce transfer produce], @lesson.reload.plan.map { |entry| entry.fetch("stage") }
    refute ArcadeStageState.where(learner_key: @learner, stage: %w[recognize trap cloze rebuild speak compress feynman]).exists?
    retry_entry = @lesson.plan.last
    assert_equal @item.fetch("id"), retry_entry.fetch("card_key")
    refute retry_entry.key?("interview_role")
    assert_equal "frontend", ArcadeContent.new.item_by_key(retry_entry.fetch("card_key")).fetch("interview_role")
  end

  private

  def record(position, **answer)
    @recorder.call(lesson: @lesson.reload, result: { exercise_id: @lesson.plan.fetch(position).fetch("exercise_id"), response_ms: 1000 }.merge(answer))
  end
end

require "test_helper"

class RecordCheckpointAttemptTest < ActiveSupport::TestCase
  test "records checkpoint attempt review schedules and misconception in one flow" do
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-cache",
      title: "Chapter 01 - Cache",
      source_path: "chapters/chapter-01-cache.md",
      position: 1,
      body_markdown: "# Cache",
      body_checksum: "cache"
    )
    checkpoint = document.checkpoints.create!(
      position: 1,
      source_label: "Fixacao",
      prompt: "Quando cache vira stale?",
      good_answer: "Quando freshness importa.",
      correction: "Defina TTL e invalidacao."
    )

    attempt = RecordCheckpointAttempt.call(
      checkpoint: checkpoint,
      attributes: {
        result: "missed",
        prediction_text: "Eu colocaria cache em tudo.",
        decision_sentence: "Eu usaria cache quando lento.",
        confidence: "low"
      }
    )

    assert_equal "cache_without_freshness", attempt.reload.misconception_key
    assert_equal [ 1, 3, 7, 14, 30 ], document.review_schedules.order(:interval_days).pluck(:interval_days)
    assert_equal 1, MisconceptionEvent.where(source_kind: "checkpoint_attempt", source_id: attempt.id).count
  end
end

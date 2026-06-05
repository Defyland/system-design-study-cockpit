require "test_helper"

class MisconceptionTrackerTest < ActiveSupport::TestCase
  test "records checkpoint misconceptions from weak attempts" do
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
    attempt = checkpoint.checkpoint_attempts.create!(
      result: "missed",
      prediction_text: "Eu colocaria cache em tudo.",
      decision_sentence: "Eu usaria cache quando lento.",
      confidence: "low"
    )

    MisconceptionTracker.record_checkpoint_attempt!(attempt)

    assert_equal "cache_without_freshness", attempt.reload.misconception_key
    assert_equal "cache_without_freshness", MisconceptionEvent.last.misconception_key
    assert_equal document, MisconceptionEvent.last.study_document
  end

  test "records simulation misconceptions when decision diverges from recommendation" do
    attempt = SimulationAttempt.create!(
      simulation_slug: "canary-rollout",
      decision: "safe",
      confidence: "high",
      input_snapshot: { "rollout" => 50 },
      output_snapshot: { "recommendedDecision" => "rollback", "feedback" => "Reverta pelo gatilho." }
    )

    MisconceptionTracker.record_simulation_attempt!(attempt)

    assert_equal "rollback_hesitation", attempt.reload.misconception_key
    assert_equal 3, MisconceptionEvent.last.severity
  end
end

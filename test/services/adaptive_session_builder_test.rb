require "test_helper"

class AdaptiveSessionBuilderTest < ActiveSupport::TestCase
  test "builds a mixed session from reviews misconceptions low confidence and contrasts" do
    chapter = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-test",
      title: "Chapter 01 - Test",
      source_path: "chapters/chapter-01-test.md",
      position: 1,
      body_markdown: "# Test",
      body_checksum: "chapter"
    )
    contrast = StudyDocument.create!(
      kind: "decision_contrast",
      slug: "01-cache-vs-replica",
      title: "Cache vs Replica",
      source_path: "decision-contrasts/01-cache-vs-replica.md",
      position: 1,
      body_markdown: "# Cache vs Replica",
      body_checksum: "contrast"
    )
    checkpoint = chapter.checkpoints.create!(
      position: 1,
      source_label: "Fixacao",
      prompt: "Qual metrica primeiro?",
      good_answer: "Erro e p95."
    )
    ReviewSchedule.create!(
      study_document: chapter,
      checkpoint: checkpoint,
      due_on: Date.current,
      interval_days: 1
    )
    checkpoint.checkpoint_attempts.create!(
      result: "hesitant",
      prediction_text: "Eu olharia CPU.",
      decision_sentence: "Eu usaria cache quando lento.",
      confidence: "medium"
    )
    MisconceptionEvent.create!(
      source_kind: "checkpoint_attempt",
      source_id: 1,
      study_document: chapter,
      misconception_key: "missing_first_metric",
      prompt: "Qual metrica primeiro?",
      correction: "Comece pelo sintoma do usuario.",
      severity: 2
    )
    SimulationAttempt.create!(
      simulation_slug: "load-balancer",
      decision: "risky",
      confidence: "medium",
      input_snapshot: {},
      output_snapshot: {}
    )

    items = AdaptiveSessionBuilder.new.call

    assert items.any? { |item| item.kind == "review" }
    assert items.any? { |item| item.kind == "misconception" }
    assert items.any? { |item| item.kind == "confidence" }
    assert items.any? { |item| item.kind == "simulation" }
    assert items.any? { |item| item.kind == "contrast" && item.title == contrast.title }
  end
end

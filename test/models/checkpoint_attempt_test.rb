require "test_helper"

class CheckpointAttemptTest < ActiveSupport::TestCase
  test "requires prediction decision sentence and confidence" do
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-test",
      title: "Chapter 01 - Test",
      source_path: "chapters/chapter-01-test.md",
      position: 1,
      body_markdown: "# Test",
      body_checksum: "abc"
    )
    checkpoint = document.checkpoints.create!(
      position: 1,
      source_label: "Fixacao",
      prompt: "Qual risco?",
      good_answer: "Risco real."
    )

    attempt = checkpoint.checkpoint_attempts.build(result: "missed")

    assert_not attempt.valid?
    assert_includes attempt.errors.attribute_names, :prediction_text
    assert_includes attempt.errors.attribute_names, :decision_sentence
    assert_includes attempt.errors.attribute_names, :confidence
  end
end

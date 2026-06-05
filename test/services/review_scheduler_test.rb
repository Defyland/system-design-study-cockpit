require "test_helper"

class ReviewSchedulerTest < ActiveSupport::TestCase
  test "schedules missed checkpoints across all review intervals and creates reminder" do
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
      good_answer: "Risco real.",
      bad_answer: "Ferramenta primeiro."
    )
    attempt = checkpoint.checkpoint_attempts.create!(
      result: "missed",
      prediction_text: "Eu escalaria primeiro.",
      decision_sentence: "Eu usaria escala quando a carga cresce.",
      confidence: "low"
    )

    ReviewScheduler.schedule!(attempt)

    assert_equal [ 1, 3, 7, 14, 30 ], document.review_schedules.order(:interval_days).pluck(:interval_days)
    assert_equal "Ferramenta primeiro.", Reminder.last.message
  end
end

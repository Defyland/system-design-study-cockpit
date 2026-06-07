require "test_helper"

class ReviewScheduleTest < ActiveSupport::TestCase
  test "requires unique schedule identity per status" do
    document = create_document
    checkpoint = create_checkpoint(document)

    ReviewSchedule.create!(
      study_document: document,
      checkpoint: checkpoint,
      interval_days: 7,
      due_on: Date.current,
      status: "pending"
    )

    duplicate = ReviewSchedule.new(
      study_document: document,
      checkpoint: checkpoint,
      interval_days: 7,
      due_on: Date.current + 1.day,
      status: "pending"
    )
    completed = ReviewSchedule.new(
      study_document: document,
      checkpoint: checkpoint,
      interval_days: 7,
      due_on: Date.current,
      status: "completed"
    )

    assert_predicate duplicate, :invalid?
    assert_includes duplicate.errors[:status], "has already been taken"
    assert_predicate completed, :valid?
  end

  private

  def create_document
    StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-review-schedule",
      title: "Chapter 01 Review Schedule",
      source_path: "chapters/chapter-01-review-schedule.md",
      position: 1,
      body_markdown: "# Chapter 01 Review Schedule",
      body_checksum: SecureRandom.hex
    )
  end

  def create_checkpoint(document)
    document.checkpoints.create!(
      position: 1,
      source_label: "Fixacao",
      prompt: "Qual risco?",
      good_answer: "Risco real."
    )
  end
end

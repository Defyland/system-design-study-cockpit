require "test_helper"

class StudyProgressTest < ActiveSupport::TestCase
  test "marks a block and status in one domain operation" do
    progress = create_progress

    progress.mark_seen!(block_position: 3, status: "read")

    assert_equal 3, progress.current_block_position
    assert_predicate progress, :read?
    assert_predicate progress.last_seen_at, :present?
  end

  test "does not persist partial progress when status is invalid" do
    progress = create_progress

    assert_raises(ArgumentError) do
      progress.mark_seen!(block_position: 3, status: "invalid")
    end

    assert_equal 1, progress.reload.current_block_position
    assert_predicate progress, :not_started?
    assert_nil progress.last_seen_at
  end

  private

  def create_progress
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-progress-test",
      title: "Chapter 01 Progress Test",
      source_path: "chapters/chapter-01-progress-test.md",
      position: 1,
      body_markdown: "# Chapter 01 Progress Test",
      body_checksum: SecureRandom.hex
    )

    document.create_study_progress!
  end
end

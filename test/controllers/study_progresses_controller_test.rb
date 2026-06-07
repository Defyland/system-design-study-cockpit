require "test_helper"

class StudyProgressesControllerTest < ActionDispatch::IntegrationTest
  test "updates the routed progress instead of trusting a document id parameter" do
    target = create_document(slug: "chapter-01-target")
    other = create_document(slug: "chapter-02-other")
    target_progress = target.create_study_progress!
    other_progress = other.create_study_progress!

    patch study_progress_path(target_progress),
      params: {
        study_document_id: other.id,
        study_progress: {
          current_block_position: 4,
          status: "read"
        }
      }

    assert_redirected_to root_path
    assert_equal 4, target_progress.reload.current_block_position
    assert_predicate target_progress, :read?
    assert_equal 1, other_progress.reload.current_block_position
    assert_predicate other_progress, :not_started?
  end

  private

  def create_document(slug:)
    StudyDocument.create!(
      kind: "chapter",
      slug: slug,
      title: slug.titleize,
      source_path: "chapters/#{slug}.md",
      position: slug[/\d+/].to_i,
      body_markdown: "# #{slug.titleize}",
      body_checksum: slug
    )
  end
end

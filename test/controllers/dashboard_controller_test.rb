require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_study_tables!
  end

  test "shows the featured interview track and 14 day plan entry point" do
    create_document(
      kind: "chapter",
      slug: "chapter-01-test",
      title: "Chapter 01 - Test",
      source_path: "chapters/chapter-01-test.md",
      position: 1
    ).create_study_progress!

    StudyDocument.create!(
      kind: "side_track_overview",
      slug: "backend-interview-foundations",
      title: "Backend Interview Foundations",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/README.md",
      position: 0,
      body_markdown: "# Backend Interview Foundations",
      body_checksum: "backend-interview-foundations",
      metadata: { "chapter_count" => 6, "side_track_area_title" => "Metodo e Entrevistas" }
    )
    StudyDocument.create!(
      kind: "side_track_overview",
      slug: "llm-foundations",
      title: "LLM Foundations",
      source_path: "areas/08-sistemas-ia/llm-foundations/README.md",
      position: 0,
      body_markdown: "# LLM Foundations",
      body_checksum: "llm-foundations"
    )

    queries = count_queries { get root_path }

    assert_operator queries, :<=, 18
    assert_response :success
    assert_includes response.body, "Backend Interview Foundations"
    assert_includes response.body, "Plano de 14 dias"
  end

  private

  def create_document(kind:, slug:, title:, source_path:, position:)
    StudyDocument.create!(
      kind: kind,
      slug: slug,
      title: title,
      source_path: source_path,
      position: position,
      body_markdown: "# #{title}",
      body_checksum: slug
    )
  end
end

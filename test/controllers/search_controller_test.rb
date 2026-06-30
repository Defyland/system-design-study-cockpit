require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_study_tables!
  end

  test "filters search results by query and quick filter" do
    StudyDocument.create!(
      kind: "side_track_chapter",
      slug: "backend-interview-foundations-01-dsa",
      title: "DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/01-dsa-operating-system-and-pattern-selection.md",
      position: 1,
      body_markdown: "# DSA\n\nSliding window and DFS.",
      body_checksum: "dsa"
    )
    StudyDocument.create!(
      kind: "backend_principle",
      slug: "rails-querying",
      title: "Rails Querying",
      source_path: "areas/09-backend-principles/cards/rails-querying.md",
      position: 1,
      body_markdown: "# Rails Querying\n\nActive Record includes.",
      body_checksum: "rails-querying"
    )

    get search_path, params: { q: "sliding", quick_filter: "dsa" }

    assert_response :success
    assert_includes response.body, "DSA Operating System and Pattern Selection"
    assert_not_includes response.body, "Rails Querying"
  end

  test "shows reference documents when requested" do
    StudyDocument.create!(
      kind: "reference_document",
      slug: "system-design-checklist",
      title: "System Design Interview Checklist",
      source_path: "areas/01-metodo-e-entrevistas/snippets/system-design-interview-checklist.md",
      position: 0,
      body_markdown: "# Checklist",
      body_checksum: "checklist"
    )

    get search_path, params: { quick_filter: "reference_docs" }

    assert_response :success
    assert_includes response.body, "System Design Interview Checklist"
  end
end

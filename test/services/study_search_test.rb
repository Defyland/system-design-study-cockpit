require "test_helper"

class StudySearchTest < ActiveSupport::TestCase
  setup do
    reset_study_tables!
  end

  test "filters by quick topic and free text" do
    dsa = create_document(
      kind: "side_track_chapter",
      slug: "backend-interview-foundations-01-dsa",
      title: "DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/01-dsa-operating-system-and-pattern-selection.md",
      body_markdown: "# DSA\n\nSliding window, hash map and binary search."
    )
    rails = create_document(
      kind: "backend_principle",
      slug: "active-record-querying",
      title: "Rails Querying",
      source_path: "areas/09-backend-principles/cards/rails-querying.md",
      body_markdown: "# Rails Querying\n\nActive Record, includes and transactions."
    )
    snippet = create_document(
      kind: "reference_document",
      slug: "areas-01-metodo-e-entrevistas-snippet",
      title: "System Design Interview Checklist",
      source_path: "areas/01-metodo-e-entrevistas/snippets/system-design-interview-checklist.md",
      body_markdown: "# Checklist\n\nPerguntas de system design."
    )

    relation = StudyDocument.where(id: [ dsa.id, rails.id, snippet.id ])

    assert_equal [ dsa.slug ], StudySearch.new(q: "binary", quick_filter: "dsa", relation: relation).results.pluck(:slug)
    assert_equal [ rails.slug ], StudySearch.new(q: "active record", quick_filter: "rails", relation: relation).results.pluck(:slug)
    assert_equal [ snippet.slug ], StudySearch.new(quick_filter: "snippets", relation: relation).results.pluck(:slug)
  end

  test "filters by reference docs and explicit kind" do
    ref = create_document(
      kind: "reference_document",
      slug: "course-outline",
      title: "Course Outline",
      source_path: "COURSE_OUTLINE.md",
      body_markdown: "# Course Outline"
    )
    story = create_document(
      kind: "interview_story_bank",
      slug: "01-ruby-rails-story-bank",
      title: "Ruby Story Bank",
      source_path: "interview/story-bank/01-ruby-rails-story-bank.md",
      body_markdown: "# Ruby Story Bank"
    )

    relation = StudyDocument.where(id: [ ref.id, story.id ])

    assert_equal [ ref.slug ], StudySearch.new(quick_filter: "reference_docs", relation: relation).results.pluck(:slug)
    assert_equal [ story.slug ], StudySearch.new(kind: "interview_story_bank", relation: relation).results.pluck(:slug)
  end

  private

  def create_document(kind:, slug:, title:, source_path:, body_markdown:)
    StudyDocument.create!(
      kind: kind,
      slug: slug,
      title: title,
      source_path: source_path,
      position: 1,
      body_markdown: body_markdown,
      body_checksum: slug
    )
  end
end

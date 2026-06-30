require "test_helper"

class HealthChecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_study_tables!
  end

  test "reports postgres and content readiness" do
    StudyDocument.create!(
      kind: "side_track_overview",
      slug: "backend-interview-foundations",
      title: "Backend Interview Foundations",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/README.md",
      position: 0,
      body_markdown: "# Backend Interview Foundations",
      body_checksum: "backend-interview-foundations"
    )
    StudyDocument.create!(
      kind: "reference_document",
      slug: "course-outline",
      title: "Course Outline",
      source_path: "COURSE_OUTLINE.md",
      position: 0,
      body_markdown: "# Course Outline",
      body_checksum: "course-outline"
    )

    get health_content_path

    assert_response :success
    payload = JSON.parse(response.body)

    assert_equal "ok", payload.fetch("status")
    assert_equal "postgresql", payload.fetch("adapter")
    assert payload.fetch("study_documents") >= 2
    assert_equal true, payload.fetch("backend_interview_foundations_present")
  end
end

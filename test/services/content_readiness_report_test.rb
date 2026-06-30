require "test_helper"

class ContentReadinessReportTest < ActiveSupport::TestCase
  setup do
    reset_study_tables!
  end

  test "is ok only when postgres content threshold and backend interview foundations are present" do
    previous_threshold = ENV["STUDY_CONTENT_MIN_DOCUMENTS"]
    ENV["STUDY_CONTENT_MIN_DOCUMENTS"] = "2"

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

    report = ContentReadinessReport.new

    assert_predicate report, :ok?
    assert_equal "ok", report.as_json.fetch(:status)
    assert_equal 2, report.as_json.fetch(:min_documents)
  ensure
    ENV["STUDY_CONTENT_MIN_DOCUMENTS"] = previous_threshold
  end

  test "is degraded when the featured side track is missing" do
    previous_threshold = ENV["STUDY_CONTENT_MIN_DOCUMENTS"]
    ENV["STUDY_CONTENT_MIN_DOCUMENTS"] = "1"

    StudyDocument.create!(
      kind: "reference_document",
      slug: "course-outline",
      title: "Course Outline",
      source_path: "COURSE_OUTLINE.md",
      position: 0,
      body_markdown: "# Course Outline",
      body_checksum: "course-outline"
    )

    report = ContentReadinessReport.new

    assert_not report.ok?
    assert_equal "degraded", report.as_json.fetch(:status)
  ensure
    ENV["STUDY_CONTENT_MIN_DOCUMENTS"] = previous_threshold
  end
end

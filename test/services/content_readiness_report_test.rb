require "test_helper"

class ContentReadinessReportTest < ActiveSupport::TestCase
  setup do
    reset_study_tables!
  end

  test "is ok in production when content is bootstrapped and sync has succeeded" do
    create_bootstrapped_content!
    sync_run = ContentSyncRun.create!(
      source_mode: "github",
      source_location: "Defyland/system-design-estudos@main",
      status: "succeeded",
      document_count: 333,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    report = ContentReadinessReport.new(production: true)

    assert_predicate report, :ok?
    assert_predicate report, :available?
    assert_equal "ok", report.as_json.fetch(:status)
    assert_equal :ok, report.http_status
    assert_equal "succeeded", report.as_json.fetch(:latest_sync_status)
    assert_equal sync_run.finished_at, report.as_json.fetch(:last_successful_sync_at)
  end

  test "is warning in production when content exists but sync has not yet been observed" do
    create_bootstrapped_content!

    report = ContentReadinessReport.new(production: true)

    assert_not report.ok?
    assert_predicate report, :available?
    assert_predicate report, :warning?
    assert_equal "warning", report.as_json.fetch(:status)
    assert_equal :ok, report.http_status
  end

  test "is warning in production when the latest sync failed after a previous success" do
    create_bootstrapped_content!
    ContentSyncRun.create!(
      source_mode: "github",
      source_location: "Defyland/system-design-estudos@main",
      status: "succeeded",
      document_count: 333,
      started_at: 10.minutes.ago,
      finished_at: 9.minutes.ago
    )
    ContentSyncRun.create!(
      source_mode: "github",
      source_location: "Defyland/system-design-estudos@main",
      status: "failed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      error_message: "RuntimeError: boom"
    )

    report = ContentReadinessReport.new(production: true)

    assert_not report.ok?
    assert_predicate report, :available?
    assert_predicate report, :warning?
    assert_equal "failed", report.as_json.fetch(:latest_sync_status)
    assert_equal "RuntimeError: boom", report.as_json.fetch(:latest_sync_error)
  end

  test "is degraded when the featured side track is missing" do
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
    assert_not report.available?
    assert_equal "degraded", report.as_json.fetch(:status)
    assert_equal :service_unavailable, report.http_status
  end

  private

  def create_bootstrapped_content!
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
  end
end

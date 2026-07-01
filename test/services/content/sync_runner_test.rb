require "test_helper"

class Content::SyncRunnerTest < ActiveSupport::TestCase
  Source = Struct.new(:documents_payload, :location, keyword_init: true) do
    def documents
      documents_payload
    end

    def source_location
      location
    end
  end

  FailingSource = Struct.new(:location, keyword_init: true) do
    def documents
      raise "boom"
    end

    def source_location
      location
    end
  end

  setup do
    reset_study_tables!
  end

  test "records a successful sync run with imported documents" do
    result = Content::SyncRunner.new(
      mode: "filesystem",
      source: Source.new(
        location: "/tmp/studies",
        documents_payload: [
          {
            kind: "reference_document",
            source_path: "COURSE_OUTLINE.md",
            body_markdown: "# Course Outline"
          }
        ]
      )
    ).call

    assert_equal 1, result.documents.size
    assert_predicate result.run, :succeeded?
    assert_equal "filesystem", result.run.source_mode
    assert_equal "/tmp/studies", result.run.source_location
    assert_equal 1, result.run.document_count
    assert_equal 1, ContentSyncRun.count
  end

  test "records a failed sync run without raising in non blocking mode" do
    result = Content::SyncRunner.new(
      mode: "github",
      source: FailingSource.new(location: "Defyland/system-design-estudos@main")
    ).call(raise_on_error: false)

    assert_empty result.documents
    assert_predicate result.run, :failed?
    assert_equal "github", result.run.source_mode
    assert_equal "Defyland/system-design-estudos@main", result.run.source_location
    assert_match "RuntimeError: boom", result.run.error_message
    assert_equal 1, ContentSyncRun.count
  end
end

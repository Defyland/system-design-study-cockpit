require "test_helper"

class EnglishArcadeSearchTest < ActiveSupport::TestCase
  test "searches stable IDs, links and authored pack metadata" do
    records = [
      Content::EnglishArcadeImporter::Record.new(
        source_id: "english-arcade:system_design:replica-lag",
        target: "system_design",
        kind: "interview_pack",
        title: "Replica lag interview",
        source_path: "content/system_design/replica-lag.yml",
        metadata: {
          "prompt" => "What would you measure first?",
          "related_source_ids" => [ "system-design-estudos:chapters/chapter-01-demo.md" ]
        },
        search_text: "replica lag measure freshness"
      ),
      Content::EnglishArcadeImporter::Record.new(
        source_id: "english-arcade:legacy:item:tech-deep-01",
        target: "legacy",
        kind: "legacy_arcade_item",
        title: "Legacy Arcade item tech-deep-01",
        source_path: "src/data/seed.ts#tech-deep-01",
        metadata: { "category" => "PERSONAL_INTRO", "difficulty" => 3 },
        search_text: "tech-deep-01 personal_intro"
      )
    ]

    result = EnglishArcadeSearch.new(records: records, query: "chapter-01-demo", include_study_documents: false).results
    assert_equal [ "english-arcade:system_design:replica-lag" ], result.map(&:source_id)

    legacy = EnglishArcadeSearch.new(records: records, query: "tech-deep-01", include_study_documents: false).results
    assert_equal [ "english-arcade:legacy:item:tech-deep-01" ], legacy.map(&:source_id)
    assert_equal "legacy_arcade_item", legacy.first.kind
  end

  test "deduplicates importer records and matching study documents by source ID" do
    source_id = "system-design-estudos:chapters/chapter-01-demo.md"
    record = Content::EnglishArcadeImporter::Record.new(
      source_id: source_id,
      target: "system_design",
      kind: "chapter",
      title: "Chapter 01 - Demo",
      source_path: "chapters/chapter-01-demo.md",
      metadata: { "canonical_source" => "chapters/chapter-01-demo.md" },
      search_text: "chapter 01 demo"
    )
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-demo",
      title: "Chapter 01 - Demo",
      source_path: "chapters/chapter-01-demo.md",
      body_markdown: "# Chapter 01 - Demo\n\nReplica lag.",
      body_checksum: "fixture"
    )

    fake_importer = Object.new
    fake_importer.define_singleton_method(:call) { [ record ] }

    results = EnglishArcadeSearch.new(
      importer: fake_importer,
      relation: StudyDocument.where(id: document.id),
      query: "chapter-01-demo"
    ).results

    assert_equal [ source_id ], results.map(&:source_id)
    assert_equal "Chapter 01 - Demo", results.first.title
  end

  test "filters by target and kind" do
    records = [
      build_record("english-arcade:system_design:a", "system_design", "interview_pack", "A", "cache"),
      build_record("english-arcade:ruby:b", "ruby", "interview_pack", "B", "cache")
    ]

    results = EnglishArcadeSearch.new(records: records, query: "cache", target: "ruby", kind: "interview_pack", include_study_documents: false).results

    assert_equal [ "english-arcade:ruby:b" ], results.map(&:source_id)
  end

  private

  def build_record(source_id, target, kind, title, text)
    Content::EnglishArcadeImporter::Record.new(
      source_id: source_id,
      target: target,
      kind: kind,
      title: title,
      source_path: "content/#{target}/#{source_id.split(":").last}.yml",
      metadata: {},
      search_text: text
    )
  end
end

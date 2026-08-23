require "test_helper"

class EnglishArcadeCorpusTest < ActiveSupport::TestCase
  test "indexes the canonical curriculum families with exact stable counts" do
    report = Content::EnglishArcadeImporter.new.result
    counts = report.records.group_by(&:kind).transform_values(&:size)

    assert_equal 14, counts.fetch("chapter")
    assert_equal 14, counts.fetch("lab")
    assert_equal 4, counts.fetch("capstone")
    assert_equal 16, counts.fetch("decision_contrast")
    assert_equal 14, counts.fetch("review_card")
    assert_equal 1, counts.fetch("curriculum")
    assert_equal 860, counts.fetch("legacy_arcade_item")
    canonical_links = report.links.reject { |link| link.relation == "pack_source" }
    assert_equal 237, canonical_links.uniq { |link| [ link.source_id, link.target_source_id, link.relation ] }.size
    assert_equal report.links.size, report.links.uniq { |link| [ link.source_id, link.target_source_id, link.relation ] }.size
    assert report.links.select { |link| link.relation == "pack_source" }.all? { |link| link.target_source_id.start_with?("system-design-estudos:") }
    assert_empty report.warnings
    pack_count = counts.fetch("interview_pack", 0)
    assert_operator pack_count, :>=, 0
    assert report.records.select { |record| record.kind == "interview_pack" }.all? { |record| record.source_id.start_with?("english-arcade:packs/") }
    refute report.records.any? { |record| record.source_id.start_with?("english-arcade:legacy:item:") && record.kind == "interview_pack" }
  end

  test "search retrieves corpus records and legacy Arcade anchors by stable identity" do
    chapter = EnglishArcadeSearch.new(query: "chapter-01-relational-scaling", include_study_documents: false).results
    assert chapter.any? { |result| result.source_id == "system-design-estudos:chapters/chapter-01-relational-scaling-and-operational-discipline.md" }

    lab = EnglishArcadeSearch.new(query: "labs/chapters/chapter-01-relational-scaling", kind: "lab", include_study_documents: false).results
    assert_equal [ "system-design-estudos:labs/chapters/chapter-01-relational-scaling-and-operational-discipline.md" ], lab.map(&:source_id)

    review = EnglishArcadeSearch.new(query: "reviews/cards/01-relational-scaling", kind: "review_card", include_study_documents: false).results
    assert_equal [ "system-design-estudos:reviews/cards/01-relational-scaling-and-operational-discipline.md" ], review.map(&:source_id)

    capstone = EnglishArcadeSearch.new(query: "capstones/04-social-feed", kind: "capstone", include_study_documents: false).results
    assert_equal [ "system-design-estudos:capstones/04-social-feed-and-event-backbone.md" ], capstone.map(&:source_id)

    contrast = EnglishArcadeSearch.new(query: "read-replica-vs-cache-aside", kind: "decision_contrast", include_study_documents: false).results
    assert_equal [ "system-design-estudos:decision-contrasts/01-read-replica-vs-cache-aside.md" ], contrast.map(&:source_id)

    legacy = EnglishArcadeSearch.new(query: "english-arcade:legacy:item:tech-deep-100", include_study_documents: false).results
    assert_equal [ "english-arcade:legacy:item:tech-deep-100" ], legacy.map(&:source_id)
    assert_equal "legacy_arcade_item", legacy.first.kind

    pack = EnglishArcadeSearch.new(query: "english-arcade:packs/dsa/dsa-01-pattern-naming", kind: "interview_pack", include_study_documents: false).results
    assert_equal [ "english-arcade:packs/dsa/dsa-01-pattern-naming" ], pack.map(&:source_id)
  end
end

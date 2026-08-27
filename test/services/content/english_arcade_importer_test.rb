require "test_helper"
require "fileutils"
require "tmpdir"
require "yaml"

class EnglishArcadeImporterTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir("english-c2-corpus"))
    @arcade = @root.join("english-arcade")
    @corpus = @root.join("system-design-estudos")
    FileUtils.mkdir_p(@arcade.join("src/data"))
    FileUtils.mkdir_p(@corpus)
  end

  teardown do
    FileUtils.remove_entry(@root) if @root.exist?
  end

  test "indexes curriculum relationships and legacy anchors without copying source prose" do
    write_fixture_corpus
    seed = <<~TYPESCRIPT
      export const seedItems = [
        {
          id: "legacy-1",
          category: "CONTRAST",
          difficulty: 2,
          ptHint: "private source hint",
          enText: "private source sentence",
          blanks: { b1: { id: "b1", kind: "connector", answers: ["although"] } },
        },
      ];
    TYPESCRIPT
    File.write(@arcade.join("src/data/seed.ts"), seed)

    importer = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade)
    report = importer.result
    kinds = report.records.group_by(&:kind).transform_values(&:size)

    assert_equal 1, kinds.fetch("chapter")
    assert_equal 1, kinds.fetch("lab")
    assert_equal 1, kinds.fetch("review_card")
    assert_equal 1, kinds.fetch("decision_contrast")
    assert_equal 1, kinds.fetch("capstone")
    assert_equal 1, kinds.fetch("curriculum")
    assert_equal 1, kinds.fetch("legacy_arcade_item")
    assert_empty report.records.select { |record| record.kind == "interview_pack" }

    chapter_id = Content::EnglishArcadeImporter.source_id_for("chapters/chapter-01-demo.md")
    lab_id = Content::EnglishArcadeImporter.source_id_for("labs/chapters/chapter-01-demo.md")
    assert_includes report.links.map(&:to_h), {
      "source_id" => chapter_id,
      "target_source_id" => lab_id,
      "relation" => "lab",
      "target_path" => "labs/chapters/chapter-01-demo.md"
    }
    assert report.links.any? do |link|
      link.source_id == Content::EnglishArcadeImporter.source_id_for("capstones/01-demo.md") &&
        link.target_source_id == chapter_id && link.relation == "pull_chapter"
    end

    legacy = report.records.find { |record| record.kind == "legacy_arcade_item" }
    assert_equal "english-arcade:legacy:item:legacy-1", legacy.source_id
    assert_equal "src/data/seed.ts#legacy-1", legacy.source_path
    refute_includes legacy.metadata.values, "private source sentence"
    assert_equal 2, legacy.metadata.fetch("difficulty")
    assert_empty report.links.map { |link| [ link.source_id, link.target_source_id, link.relation ] }.tally.select { |_key, count| count > 1 }
  end

  test "repeated imports preserve stable IDs and source checksums" do
    write_fixture_corpus
    File.write(@arcade.join("src/data/seed.ts"), "export const seedItems = [];\n")

    first = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade).result
    second = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade).result

    assert_equal first.records.map(&:source_id), second.records.map(&:source_id)
    assert_equal first.records.map(&:source_checksum), second.records.map(&:source_checksum)
    assert first.records.all? { |record| record.source_checksum.present? }
    assert_equal first.links.map(&:to_h), second.links.map(&:to_h)
    assert_equal "# Chapter 01 - Demo\n\nCanonical source body.\n", File.read(@corpus.join("chapters/chapter-01-demo.md"))
  end

  test "persists links only onto matching study documents" do
    write_fixture_corpus
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-demo",
      title: "Chapter 01 - Demo",
      source_path: "chapters/chapter-01-demo.md",
      body_markdown: "# Chapter 01 - Demo",
      body_checksum: "fixture"
    )
    before_count = StudyDocument.count

    report = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade, persist: true).import!

    assert_equal before_count, StudyDocument.count
    assert_equal 1, report.persisted_count
    metadata = document.reload.metadata
    assert_equal Content::EnglishArcadeImporter.source_id_for(document.source_path), metadata.fetch("source_id")
    assert_equal "chapter", metadata.dig("english_arcade", "kind")
    assert_equal document.source_path, metadata.dig("english_arcade", "source_path")
  end

  test "validates structured interview packs but keeps legacy items out of that contract" do
    write_fixture_corpus
    records = [
      {
        source_id: "packs/system-design/replica-lag",
        target: "system_design",
        title: "Replica lag interview pack",
        prompt: "What would you measure first?",
        context: "A read path is stale.",
        answer: "I would measure lag and freshness before changing topology.",
        distractors: [ "Add a queue immediately.", "Shard every table." ],
        feedback: "Use calibrated language and name the metric.",
        rephrase: "Give the same answer with a caveat.",
        sources: [ { repo: "system-design-estudos", path: "chapters/chapter-01-demo.md" }, { repo: "system-design-estudos", path: "chapters/chapter-01-demo.md" }, { repo: "original", path: "english-arcade/replica-lag" } ]
      }
    ]

    importer = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade, external_records: records)
    error = assert_raises(Content::EnglishArcadeImporter::ValidationError) { importer.validate! }
    assert_includes error.errors, "canonical pack career: missing pack"
    pack = importer.records.find { |record| record.kind == "interview_pack" }
    assert_equal "english-arcade:packs/system-design/replica-lag", pack.source_id
    assert_equal "system_design", pack.target
    assert_empty importer.records.select { |record| record.kind == "legacy_arcade_item" }
    assert_equal 1, importer.result.links.count { |link| link.source_id == pack.source_id && link.relation == "pack_source" }
    assert importer.result.links.any? do |link|
      link.source_id == pack.source_id &&
        link.target_source_id == Content::EnglishArcadeImporter.source_id_for("chapters/chapter-01-demo.md") &&
        link.relation == "pack_source"
    end
    readiness = importer.pack_readiness
    assert_equal EnglishArcade::Schema::PUBLISHABLE_ITEMS_PER_TARGET, readiness.fetch("minimum_items_per_target")
    assert_equal 1, readiness.dig("targets", "system_design", "item_count")
    assert_includes readiness.fetch("missing_targets"), "career"
    assert_equal EnglishArcade::Schema::TARGETS.length, readiness.fetch("missing_targets").length + readiness.fetch("target_count")
    refute_includes readiness.to_s, records.first.fetch(:answer)

    incomplete_record = records.first.dup
    incomplete_record.delete(:answer)
    incomplete = Content::EnglishArcadeImporter.new(
      corpus_root: @corpus,
      arcade_root: @arcade,
      external_records: [ incomplete_record ]
    )
    error = assert_raises(Content::EnglishArcadeImporter::ValidationError) { incomplete.validate! }
    assert_includes error.errors, "english-arcade:packs/system-design/replica-lag: missing answer"
  end

  test "health evidence reports pack minima without serializing private answers" do
    write_fixture_corpus
    load Rails.root.join("db/seeds/english_arcade_corpus.rb")
    answer = "private answer that must not cross the health boundary"
    payload = EnglishArcadeCorpus.health_payload(
      corpus_root: @corpus,
      arcade_root: @arcade,
      external_records: [ {
        source_id: "packs/system_design/redacted",
        target: "system_design",
        prompt: "A prompt",
        context: "A context",
        answer: answer,
        distractors: [ "One", "Two" ],
        feedback: "Feedback",
        rephrase: "Rephrase"
      } ]
    )

    assert_equal "warning", payload.fetch("status")
    assert_equal EnglishArcade::Schema::PUBLISHABLE_ITEMS_PER_TARGET, payload.dig("pack_readiness", "minimum_items_per_target")
    assert_equal 1, payload.dig("pack_readiness", "item_count")
    refute_includes JSON.generate(payload), answer
    refute payload.key?("database")
  end

  test "strict readiness rejects incomplete canonical packs without exposing their prose" do
    write_fixture_corpus
    pack_directory, private_answer = write_invalid_canonical_pack_directory
    invalid_pack = YAML.safe_load_file(pack_directory.join("rails.yml"), aliases: false)
    invalid_item = invalid_pack.fetch("items").first
    validator = EnglishArcade::PackValidator.new(invalid_pack, strict: true)

    assert_equal 12, invalid_pack.fetch("items").size
    %w[prompt context best_answer distractors feedback rephrase sources].each do |field|
      assert invalid_item.key?(field), "fixture must preserve superficial #{field}"
    end
    refute_predicate validator, :valid?
    assert validator.errors.any? { |error| error.path.end_with?(".feynman") }
    assert validator.errors.any? { |error| error.path.end_with?(".recall") }

    importer = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade)
    readiness = importer.pack_readiness

    refute readiness.fetch("ready")
    assert_operator readiness.dig("targets", "rails", "validation_error_count"), :>, 0
    error = assert_raises(Content::EnglishArcadeImporter::ValidationError) { importer.validate! }
    assert_match(/canonical pack rails: strict validation failed/, error.message)
    refute_includes error.message, private_answer

    load Rails.root.join("db/seeds/english_arcade_corpus.rb")
    importer_health = EnglishArcadeCorpus.health_payload(corpus_root: @corpus, arcade_root: @arcade)
    refute importer_health.dig("pack_readiness", "ready")
    assert_operator importer_health.fetch("validation_error_count"), :>, 0
    refute_includes JSON.generate(importer_health), private_answer

    report_health = ContentReadinessReport.new(arcade_pack_directory: pack_directory).as_json
    report_readiness = report_health.fetch(:english_arcade_pack_readiness)
    refute report_readiness.fetch("ready")
    assert_operator report_readiness.dig("targets", "rails", "validation_error_count"), :>, 0
    refute_includes JSON.generate(report_health), private_answer
  end

  test "external records cannot claim strict release readiness without observed pack validation" do
    write_fixture_corpus
    answer = "private external answer that must stay outside readiness"
    records = Content::EnglishArcadeImporter::TARGETS.flat_map do |target|
      12.times.map do |index|
        {
          source_id: "external/#{target}/#{index}", target: target,
          prompt: "Prompt #{target} #{index}", context: "Context #{target} #{index}", answer: answer,
          distractors: [ "one", "two" ], feedback: "Feedback #{target}", rephrase: "Rephrase #{target}"
        }
      end
    end
    importer = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade, external_records: records)
    readiness = importer.pack_readiness

    refute readiness.fetch("ready")
    assert readiness.fetch("targets").values.none? { |summary| summary.fetch("strict_validation_observed") }
    error = assert_raises(Content::EnglishArcadeImporter::ValidationError) { importer.validate! }
    assert_includes error.message, "strict validation was not observed"
    refute_includes error.message, answer

    load Rails.root.join("db/seeds/english_arcade_corpus.rb")
    health = EnglishArcadeCorpus.health_payload(corpus_root: @corpus, arcade_root: @arcade, external_records: records)
    assert_equal "warning", health.fetch("status")
    refute_includes JSON.generate(health), answer
  end

  test "missing or invalid experience packs fail closed without exposing evidence" do
    write_fixture_corpus
    pack_directory, private_answer = write_invalid_canonical_pack_directory
    FileUtils.rm(pack_directory.join("go-experience.yml"))

    importer = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade)
    readiness = importer.pack_readiness
    refute readiness.fetch("ready")
    assert_includes readiness.fetch("missing_targets"), "go_experience"
    error = assert_raises(Content::EnglishArcadeImporter::ValidationError) { importer.validate! }
    assert_includes error.errors, "canonical pack go_experience: missing pack"
    refute_includes error.message, private_answer

    report = ContentReadinessReport.new(arcade_pack_directory: pack_directory).as_json
    refute report.fetch(:english_arcade_pack_readiness).fetch("ready")
    assert_includes report.fetch(:english_arcade_pack_readiness).fetch("missing_targets"), "go_experience"
    refute_includes JSON.generate(report), private_answer
  end

  test "invalid experience provenance is not downgraded to a generic card pack" do
    write_fixture_corpus
    pack_directory, private_answer = write_invalid_canonical_pack_directory
    path = pack_directory.join("elixir-experience.yml")
    pack = YAML.safe_load_file(path, aliases: false)
    pack.fetch("items").first.delete("provenance")
    File.write(path, YAML.dump(pack))

    importer = Content::EnglishArcadeImporter.new(corpus_root: @corpus, arcade_root: @arcade)
    readiness = importer.pack_readiness
    refute readiness.fetch("ready")
    assert_operator readiness.dig("targets", "elixir_experience", "validation_error_count"), :>, 0
    error = assert_raises(Content::EnglishArcadeImporter::ValidationError) { importer.validate! }
    assert_match(/canonical pack elixir_experience: strict validation failed/, error.message)
    refute_includes error.message, private_answer
  end

  private

  def write_fixture_corpus
    FileUtils.mkdir_p(@corpus.join("chapters"))
    FileUtils.mkdir_p(@corpus.join("labs/chapters"))
    FileUtils.mkdir_p(@corpus.join("reviews/cards"))
    FileUtils.mkdir_p(@corpus.join("decision-contrasts"))
    FileUtils.mkdir_p(@corpus.join("capstones"))
    File.write(@corpus.join("chapters/chapter-01-demo.md"), "# Chapter 01 - Demo\n\nCanonical source body.\n")
    File.write(@corpus.join("labs/chapters/chapter-01-demo.md"), "# Lab - Chapter 01\n\nDrill source.\n")
    File.write(@corpus.join("reviews/cards/01-demo.md"), "# Review Card 01\n\nRecall source.\n")
    File.write(@corpus.join("decision-contrasts/01-demo.md"), "# Contrast 01\n\nDecision source.\n")
    File.write(@corpus.join("capstones/01-demo.md"), "# Capstone 01\n\nCapstone source.\n\n[Chapter 01](../chapters/chapter-01-demo.md)\n")
    File.write(@corpus.join("curriculum.yml"), <<~YAML)
      version: 2
      title: Demo Curriculum
      canonical_source: curriculum.yml
      phases:
        - id: fase-1
          title: Fase 1
      chapters:
        - id: demo
          number: 1
          title: Chapter 01 - Demo
          path: chapters/chapter-01-demo.md
          phase: fase-1
          lab:
            path: labs/chapters/chapter-01-demo.md
          review_card:
            path: reviews/cards/01-demo.md
          suggested_contrast:
            path: decision-contrasts/01-demo.md
    YAML
  end

  def write_invalid_canonical_pack_directory
    destination = @arcade.join("db/seeds")
    FileUtils.mkdir_p(destination)
    FileUtils.cp_r(Rails.root.join("db/seeds/english_arcade"), destination)
    pack_directory = destination.join("english_arcade")
    path = pack_directory.join("rails.yml")
    pack = YAML.safe_load_file(path, aliases: false)
    private_answer = pack.fetch("items").first.fetch("best_answer")
    pack.fetch("items").first.delete("feynman")
    pack.fetch("items").first.delete("recall")
    File.write(path, YAML.dump(pack))

    [ pack_directory, private_answer ]
  end
end

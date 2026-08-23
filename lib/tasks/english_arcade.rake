require "json"
require "pathname"

namespace :english_arcade do
  desc "Index English Arcade records and link them to imported study documents"
  task import: :environment do
    load Rails.root.join("db/seeds/english_arcade_corpus.rb") unless defined?(EnglishArcadeCorpus)

    report = EnglishArcadeCorpus.seed!(persist: ENV.fetch("ENGLISH_ARCADE_PERSIST", "true") != "false")
    puts JSON.pretty_generate(
      "records" => report.records.size,
      "links" => report.links.size,
      "persisted_documents" => report.persisted_count,
      "warnings" => report.warnings,
      "pack_readiness" => report.pack_readiness
    )
  end

  desc "Validate Arcade records and source identity requirements"
  task validate: :environment do
    load Rails.root.join("db/seeds/english_arcade_corpus.rb") unless defined?(EnglishArcadeCorpus)

    EnglishArcadeCorpus.validate!
    report = EnglishArcadeCorpus.manifest
    puts JSON.pretty_generate(
      "valid" => true,
      "records" => report.fetch("records").size,
      "links" => report.fetch("links").size,
      "warnings" => report.fetch("warnings"),
      "pack_readiness" => report.fetch("pack_readiness")
    )
  rescue Content::EnglishArcadeImporter::ValidationError => error
    warn JSON.pretty_generate("valid" => false, "errors" => error.errors)
    abort("English Arcade validation failed")
  end

  desc "Print the stable English Arcade/corpus manifest"
  task manifest: :environment do
    load Rails.root.join("db/seeds/english_arcade_corpus.rb") unless defined?(EnglishArcadeCorpus)

    puts JSON.pretty_generate(EnglishArcadeCorpus.manifest)
  end

  desc "Print redacted Arcade readiness evidence for health checks"
  task health: :environment do
    load Rails.root.join("db/seeds/english_arcade_corpus.rb") unless defined?(EnglishArcadeCorpus)

    puts JSON.pretty_generate(EnglishArcadeCorpus.health_payload)
  end

  desc "Search Arcade packs and linked study corpus (QUERY=... TARGET=... KIND=...)"
  task search: :environment do
    results = EnglishArcadeSearch.new(
      query: ENV["QUERY"],
      target: ENV["TARGET"],
      kind: ENV["KIND"]
    ).results

    puts JSON.pretty_generate(results.map(&:to_h))
  end

  desc "Run non-destructive release checks for source paths and deduplication"
  task qa: :environment do
    load Rails.root.join("db/seeds/english_arcade_corpus.rb") unless defined?(EnglishArcadeCorpus)

    report = EnglishArcadeCorpus.manifest
    records = report.fetch("records")
    pack_readiness = report.fetch("pack_readiness")
    source_ids = records.map { |record| record.fetch("source_id") }
    source_paths = records.map { |record| record.fetch("source_path") }
    checks = {
      "valid" => true,
      "records_have_unique_source_ids" => source_ids.uniq.size == source_ids.size,
      "records_have_unique_source_paths_per_id" => records.group_by { |record| record.fetch("source_id") }.values.all? { |group| group.map { |record| record.fetch("source_path") }.uniq.size == 1 },
      "links_have_stable_source_ids" => report.fetch("links").all? { |link| link.fetch("source_id").include?(":") && link.fetch("target_source_id").include?(":") },
      "link_target_paths_are_relative" => report.fetch("links").none? { |link| Pathname(link.fetch("target_path")).absolute? },
      "source_paths_are_relative" => source_paths.none? { |path| Pathname(path).absolute? },
      "pack_minima_ready" => pack_readiness.fetch("ready"),
      "pack_readiness" => pack_readiness,
      "warnings_empty" => report.fetch("warnings").empty?,
      "warnings" => report.fetch("warnings")
    }
    checks["valid"] = checks.except("warnings", "pack_readiness").values.all?
    puts JSON.pretty_generate(checks)
    abort("English Arcade QA failed") unless checks.fetch("valid")
  end
end

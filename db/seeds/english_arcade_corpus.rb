# Stable, repeatable corpus integration entry point.
#
# This file is intentionally not required by db/seeds.rb: deployments can run
# the explicit english_arcade:import task after the normal study sync.  That
# ordering lets a later content sync remain authoritative for Markdown while
# this adapter reapplies only the Arcade metadata links.
module EnglishArcadeCorpus
  module_function

  def importer(**options)
    Content::EnglishArcadeImporter.new(**options)
  end

  def manifest(**options)
    importer(**options).result.to_h
  end

  def validate!(**options)
    importer(**options).validate!
  end

  # Health/readiness payload intentionally contains only aggregate counts,
  # required field names and validation totals.  It never serializes pack
  # prompts, answers, distractors, feedback or database configuration.
  def health_payload(**options)
    source = importer(**options)
    report = source.result
    errors = source.validation_errors(report.records)
    readiness = report.pack_readiness
    {
      "status" => errors.empty? && report.warnings.empty? && readiness.fetch("ready") ? "ok" : "warning",
      "records" => report.records.size,
      "links" => report.links.size,
      "warnings_count" => report.warnings.size,
      "validation_error_count" => errors.size,
      "pack_readiness" => readiness
    }
  end

  def seed!(persist: true, **options)
    importer(**options.merge(persist: persist)).import!
  end

  alias import! seed!
  module_function :import!
end

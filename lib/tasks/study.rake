require "json"

namespace :study do
  desc "Sync study content from filesystem or GitHub"
  task sync_content: :environment do
    mode = ENV.fetch("STUDY_CONTENT_MODE", Rails.env.production? ? "github" : "filesystem")
    source = mode == "github" ? Content::GithubSource.new : Content::FilesystemSource.new

    documents = Content::Importer.new(source: source).call
    puts "Imported #{documents.size} study documents from #{mode}."
  end

  desc "Print content readiness and fail when PostgreSQL or content requirements are not met"
  task readiness: :environment do
    report = ContentReadinessReport.new

    puts JSON.pretty_generate(report.as_json)
    abort("Content readiness failed") unless report.ok?
  end
end

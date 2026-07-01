require "json"

namespace :study do
  desc "Sync study content from filesystem or GitHub"
  task sync_content: :environment do
    result = Content::SyncRunner.new.call
    puts "Imported #{result.documents.size} study documents from #{result.run.source_mode}."
  end

  desc "Sync study content but never fail the process"
  task sync_content_non_blocking: :environment do
    result = Content::SyncRunner.new.call(raise_on_error: false)
    puts "Imported #{result.documents.size} study documents from #{result.run.source_mode}." if result.run&.succeeded?
  end

  desc "Print content readiness and fail when PostgreSQL or content requirements are not met"
  task readiness: :environment do
    report = ContentReadinessReport.new

    puts JSON.pretty_generate(report.as_json)
    abort("Content readiness failed") unless report.available?
  end
end

namespace :study do
  desc "Sync study content from filesystem or GitHub"
  task sync_content: :environment do
    mode = ENV.fetch("STUDY_CONTENT_MODE", Rails.env.production? ? "github" : "filesystem")
    source = mode == "github" ? Content::GithubSource.new : Content::FilesystemSource.new

    documents = Content::Importer.new(source: source).call
    puts "Imported #{documents.size} study documents from #{mode}."
  end
end

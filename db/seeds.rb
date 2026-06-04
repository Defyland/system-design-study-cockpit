mode = ENV.fetch("STUDY_CONTENT_MODE", Rails.env.production? ? "github" : "filesystem")
source = mode == "github" ? Content::GithubSource.new : Content::FilesystemSource.new

Content::Importer.new(source: source).call

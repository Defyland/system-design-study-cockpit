require "base64"
require "json"
require "net/http"

module Content
  class GithubSource
    DOCUMENT_DIRECTORIES = {
      "chapter" => "chapters",
      "lab" => "labs/chapters",
      "review_card" => "reviews/cards",
      "capstone" => "capstones"
    }.freeze

    FILE_PATTERNS = {
      "chapter" => /\Achapter-.*\.md\z/,
      "lab" => /\Achapter-.*\.md\z/,
      "review_card" => /\A\d{2}-.*\.md\z/,
      "capstone" => /\A\d{2}-.*\.md\z/
    }.freeze

    def initialize(
      repo: ENV.fetch("STUDY_CONTENT_GITHUB_REPO", "Defyland/system-design-estudos"),
      ref: ENV.fetch("STUDY_CONTENT_GITHUB_REF", "main"),
      token: ENV["GITHUB_TOKEN"]
    )
      @repo = repo
      @ref = ref
      @token = token
    end

    def documents
      DOCUMENT_DIRECTORIES.flat_map do |kind, directory|
        list_directory(directory)
          .select { |entry| entry.fetch("type") == "file" && entry.fetch("name").match?(FILE_PATTERNS.fetch(kind)) }
          .sort_by { |entry| entry.fetch("path") }
          .map do |entry|
            {
              kind: kind,
              source_path: entry.fetch("path"),
              body_markdown: fetch_file(entry.fetch("path"))
            }
          end
      end
    end

    private

    def list_directory(path)
      response = request_json(contents_uri(path))
      raise "GitHub path is not a directory: #{path}" unless response.is_a?(Array)

      response
    end

    def fetch_file(path)
      response = request_json(contents_uri(path))
      content = response.fetch("content")
      Base64.decode64(content)
    end

    def contents_uri(path)
      URI("https://api.github.com/repos/#{@repo}/contents/#{path}?ref=#{@ref}")
    end

    def request_json(uri)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = "system-design-study-cockpit"
      request["Authorization"] = "Bearer #{@token}" if @token.present?

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      raise "GitHub request failed: #{uri.path} #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end

require "base64"
require "json"
require "net/http"
require "yaml"

module Content
  class GithubSource
    DOCUMENT_SPECS = ContentKind.github_specs.freeze

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
      imported = DOCUMENT_SPECS.flat_map do |kind, spec|
        Array(spec.fetch(:directory)).flat_map do |directory|
          entries = spec[:recursive] ? list_tree(directory) : list_directory(directory)

          entries
            .select { |entry| importable_file?(entry, spec.fetch(:pattern), recursive: spec[:recursive]) }
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

      imported.concat(side_track_documents)
      imported.uniq { |document| [ document.fetch(:kind), document.fetch(:source_path) ] }
    end

    def curriculum
      YAML.safe_load(fetch_file("curriculum.yml"), aliases: true) || {}
    rescue StandardError
      {}
    end

    private

    def importable_file?(entry, pattern, recursive: false)
      return false unless entry.fetch("type") == "file"

      target = recursive ? entry.fetch("path") : entry.fetch("name")
      target.match?(pattern)
    end

    def list_directory(path)
      response = request_json(contents_uri(path))
      raise "GitHub path is not a directory: #{path}" unless response.is_a?(Array)

      response
    end

    def list_tree(path)
      list_directory(path).flat_map do |entry|
        case entry.fetch("type")
        when "dir"
          list_tree(entry.fetch("path"))
        when "file"
          entry
        else
          []
        end
      end
    end

    def fetch_file(path)
      response = request_json(contents_uri(path))
      content = response.fetch("content")
      Base64.decode64(content)
    end

    def contents_uri(path)
      normalized_path = path.presence
      URI("https://api.github.com/repos/#{@repo}/contents/#{normalized_path}?ref=#{@ref}")
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

    def side_track_documents
      CurriculumGraph.side_track_document_specs(curriculum).map do |spec|
        {
          kind: spec.fetch(:kind),
          source_path: spec.fetch(:source_path),
          body_markdown: fetch_file(spec.fetch(:source_path))
        }
      end
    rescue StandardError
      []
    end
  end
end

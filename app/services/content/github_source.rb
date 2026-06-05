require "base64"
require "json"
require "net/http"
require "yaml"

module Content
  class GithubSource
    DOCUMENT_SPECS = {
      "chapter" => { directory: "chapters", pattern: /\Achapter-.*\.md\z/ },
      "lab" => { directory: "labs/chapters", pattern: /\Achapter-.*\.md\z/ },
      "review_card" => { directory: "reviews/cards", pattern: /\A\d{2}-.*\.md\z/ },
      "capstone" => { directory: "capstones", pattern: /\A\d{2}-.*\.md\z/ },
      "foundation" => { directory: "areas/06-foundations-distribuidas/topics", pattern: /\A.+\.md\z/ },
      "component_card" => { directory: "areas/07-componentes-de-sistemas/cards", pattern: /\A.+\.md\z/ },
      "simulation_lab" => { directory: "simulation-labs", pattern: /\A(?!README\.md).+\.md\z/ },
      "ai_system" => { directory: "areas/08-sistemas-ia/topics", pattern: /\A.+\.md\z/ },
      "real_world_case" => { directory: "real-world-cases", pattern: %r{/README\.md\z}, recursive: true },
      "decision_contrast" => { directory: "decision-contrasts", pattern: /\A\d{2}-.*\.md\z/ }
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
      DOCUMENT_SPECS.flat_map do |kind, spec|
        entries = spec[:recursive] ? list_tree(spec.fetch(:directory)) : list_directory(spec.fetch(:directory))

        entries
          .select { |entry| importable_file?(entry, spec.fetch(:pattern)) }
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

    def curriculum
      YAML.safe_load(fetch_file("curriculum.yml"), aliases: true) || {}
    rescue StandardError
      {}
    end

    private

    def importable_file?(entry, pattern)
      return false unless entry.fetch("type") == "file"

      entry.fetch("path").match?(pattern) || entry.fetch("name").match?(pattern)
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

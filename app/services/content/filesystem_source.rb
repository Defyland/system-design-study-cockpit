require "yaml"

module Content
  class FilesystemSource
    DOCUMENT_PATTERNS = ContentKind.filesystem_patterns.freeze

    def initialize(root_path: ENV.fetch("STUDY_CONTENT_PATH", "../system-design-estudos"))
      @root_path = Pathname(root_path).expand_path(Rails.root)
    end

    def documents
      DOCUMENT_PATTERNS.flat_map do |kind, pattern|
        Dir.glob(@root_path.join(pattern)).sort.reject { |path| skip_document?(kind, path) }.map do |path|
          pathname = Pathname(path)

          {
            kind: kind,
            source_path: pathname.relative_path_from(@root_path).to_s,
            body_markdown: pathname.read
          }
        end
      end
    end

    def curriculum
      path = @root_path.join("curriculum.yml")
      return {} unless path.exist?

      YAML.safe_load(path.read, aliases: true) || {}
    end

    private

    def skip_document?(kind, path)
      kind == "simulation_lab" && File.basename(path) == "README.md"
    end
  end
end

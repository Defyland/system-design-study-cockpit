require "yaml"

module Content
  class FilesystemSource
    DOCUMENT_PATTERNS = ContentKind.filesystem_patterns.freeze

    def initialize(root_path: ENV.fetch("STUDY_CONTENT_PATH", "../system-design-estudos"))
      @root_path = Pathname(root_path).expand_path(Rails.root)
    end

    def documents
      imported = DOCUMENT_PATTERNS.flat_map do |kind, pattern|
        Array(pattern).flat_map do |single_pattern|
          Dir.glob(@root_path.join(single_pattern)).sort.reject { |path| skip_document?(kind, path) }.map do |path|
            pathname = Pathname(path)

            {
              kind: kind,
              source_path: pathname.relative_path_from(@root_path).to_s,
              body_markdown: pathname.read
            }
          end
        end
      end

      imported.concat(side_track_documents)
      imported.uniq { |document| [ document.fetch(:kind), document.fetch(:source_path) ] }
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

    def side_track_documents
      CurriculumGraph.side_track_document_specs(curriculum).filter_map do |spec|
        pathname = @root_path.join(spec.fetch(:source_path))
        next unless pathname.exist?

        {
          kind: spec.fetch(:kind),
          source_path: spec.fetch(:source_path),
          body_markdown: pathname.read
        }
      end
    end
  end
end

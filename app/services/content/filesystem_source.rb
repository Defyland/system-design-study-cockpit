module Content
  class FilesystemSource
    DOCUMENT_PATTERNS = {
      "chapter" => "chapters/chapter-*.md",
      "lab" => "labs/chapters/chapter-*.md",
      "review_card" => "reviews/cards/*.md",
      "capstone" => "capstones/[0-9][0-9]-*.md"
    }.freeze

    def initialize(root_path: ENV.fetch("STUDY_CONTENT_PATH", "../system-design-estudos"))
      @root_path = Pathname(root_path).expand_path(Rails.root)
    end

    def documents
      DOCUMENT_PATTERNS.flat_map do |kind, pattern|
        Dir.glob(@root_path.join(pattern)).sort.map do |path|
          pathname = Pathname(path)

          {
            kind: kind,
            source_path: pathname.relative_path_from(@root_path).to_s,
            body_markdown: pathname.read
          }
        end
      end
    end
  end
end

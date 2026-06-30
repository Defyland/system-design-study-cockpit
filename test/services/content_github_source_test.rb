require "test_helper"

class ContentGithubSourceTest < ActiveSupport::TestCase
  test "recursive reference document import matches full paths instead of every README name" do
    fake_source_class = Class.new(Content::GithubSource) do
      def list_directory(_path)
        []
      end

      def list_tree(path)
        return [] unless path == ""

        [
          { "type" => "file", "name" => "README.md", "path" => "README.md" },
          { "type" => "file", "name" => "notes.md", "path" => "areas/01-metodo-e-entrevistas/notes.md" },
          { "type" => "file", "name" => "README.md", "path" => "real-world-cases/05-product-scenarios/meta-news-feed-ranking/README.md" }
        ]
      end

      def fetch_file(_path)
        "# Title\n\nBody"
      end

      def curriculum
        {}
      end
    end

    source = fake_source_class.new(repo: "test/repo", ref: "main", token: "token")
    documents = source.documents.select { |document| document.fetch(:kind) == "reference_document" }

    assert_equal [ "README.md", "areas/01-metodo-e-entrevistas/notes.md" ], documents.map { |document| document.fetch(:source_path) }
  end
end

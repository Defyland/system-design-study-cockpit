require "test_helper"

class ContentImporterTest < ActiveSupport::TestCase
  FakeSource = Struct.new(:documents)

  test "imports documents with blocks checkpoints and progress" do
    documents = [
      {
        kind: "chapter",
        source_path: "chapters/chapter-01-test.md",
        body_markdown: <<~MARKDOWN
          # Chapter 01 - Test

          ## Onde Isso Aparece Antes da Teoria

          Texto base.

          ### Fixacao Relampago

          - `Pergunta`: qual requisito?
          - `Resposta curta`: o menor verdadeiro.
        MARKDOWN
      }
    ]

    imported = Content::Importer.new(source: FakeSource.new(documents)).call
    document = imported.first

    assert_predicate document, :persisted?
    assert_equal "chapter", document.kind
    assert_equal 1, document.position
    assert_equal 1, document.checkpoints.count
    assert document.study_blocks.any?
    assert_predicate document.study_progress, :not_started?
  end

  test "does not recreate blocks when checksum is unchanged" do
    source = FakeSource.new([
      {
        kind: "chapter",
        source_path: "chapters/chapter-01-test.md",
        body_markdown: "# Chapter 01 - Test\n\nTexto base."
      }
    ])

    importer = Content::Importer.new(source: source)
    first = importer.call.first
    block_ids = first.study_blocks.pluck(:id)

    second = importer.call.first

    assert_equal block_ids, second.study_blocks.pluck(:id)
  end
end

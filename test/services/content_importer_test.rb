require "test_helper"

class ContentImporterTest < ActiveSupport::TestCase
  FakeSource = Struct.new(:documents, :curriculum)

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

    imported = Content::Importer.new(source: FakeSource.new(documents, nil)).call
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
    ], nil)

    importer = Content::Importer.new(source: source)
    first = importer.call.first
    block_ids = first.study_blocks.pluck(:id)

    second = importer.call.first

    assert_equal block_ids, second.study_blocks.pluck(:id)
  end

  test "removes stale documents for synced kinds" do
    StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-99-old",
      title: "Old Chapter",
      source_path: "chapters/chapter-99-old.md",
      position: 99,
      body_markdown: "# Old Chapter",
      body_checksum: "old"
    )

    source = FakeSource.new([
      {
        kind: "chapter",
        source_path: "chapters/chapter-01-new.md",
        body_markdown: "# Chapter 01 - New\n\nTexto base."
      }
    ], nil)

    Content::Importer.new(source: source).call

    assert_nil StudyDocument.find_by(slug: "chapter-99-old")
    assert StudyDocument.find_by(slug: "chapter-01-new")
  end

  test "does not prune when source is empty" do
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-existing",
      title: "Existing Chapter",
      source_path: "chapters/chapter-01-existing.md",
      position: 1,
      body_markdown: "# Existing Chapter",
      body_checksum: "existing"
    )

    Content::Importer.new(source: FakeSource.new([], nil)).call

    assert StudyDocument.find_by(id: document.id)
  end

  test "caches curriculum when source exposes one" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    source = FakeSource.new([], { "version" => 1, "phases" => [ { "id" => "fase-1" } ] })

    Content::Importer.new(source: source).call

    assert_equal 1, Rails.cache.read("study_content/curriculum").fetch("version")
  ensure
    Rails.cache = previous_cache
  end

  test "imports decision contrasts as study documents" do
    source = FakeSource.new([
      {
        kind: "decision_contrast",
        source_path: "decision-contrasts/01-cache-vs-replica.md",
        body_markdown: "# Cache vs Replica\n\nCompare as decisoes."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :decision_contrast?
    assert_equal "01-cache-vs-replica", document.slug
  end
end

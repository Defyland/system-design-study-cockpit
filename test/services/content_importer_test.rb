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

  test "enriches imported documents from curriculum manifest" do
    source = FakeSource.new([
      {
        kind: "chapter",
        source_path: "chapters/chapter-03-idempotent-writes.md",
        body_markdown: "# Chapter 03 - Idempotent Writes\n\nTexto base."
      },
      {
        kind: "lab",
        source_path: "labs/chapters/chapter-03-idempotent-writes.md",
        body_markdown: "# Lab 03\n\nDrill rapido."
      }
    ], curriculum)

    imported = Content::Importer.new(source: source).call
    chapter = imported.detect(&:chapter?)
    lab = imported.detect(&:lab?)

    assert_equal 3, chapter.position
    assert_equal "Fase 1 - Base forte", chapter.phase
    assert_equal "Stripe - Idempotent Payments", chapter.metadata.fetch("primary_case_title")
    assert_equal "03-filas-e-consistencia", chapter.metadata.fetch("primary_area_id")
    assert_equal "chapter-03-idempotent-writes", lab.metadata.fetch("chapter_slug")
    assert_equal 3, lab.position
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

  private

  def curriculum
    {
      "phases" => [
        { "id" => "fase-1", "title" => "Fase 1 - Base forte" }
      ],
      "areas" => [
        { "id" => "03-filas-e-consistencia", "title" => "Filas e Consistencia" }
      ],
      "chapters" => [
        {
          "id" => "idempotent-writes-under-ambiguous-failure",
          "number" => 3,
          "title" => "Idempotent Writes",
          "slug" => "chapter-03-idempotent-writes",
          "path" => "chapters/chapter-03-idempotent-writes.md",
          "phase" => "fase-1",
          "primary_area" => "03-filas-e-consistencia",
          "secondary_areas" => [],
          "notes" => [ "areas/03-filas-e-consistencia/notes.md" ],
          "primary_case" => {
            "id" => "stripe-idempotent-payments",
            "title" => "Stripe - Idempotent Payments",
            "path" => "real-world-cases/stripe/README.md"
          },
          "complementary_cases" => [],
          "lab" => { "path" => "labs/chapters/chapter-03-idempotent-writes.md" },
          "review_card" => { "path" => "reviews/cards/03-idempotent-writes.md" },
          "suggested_contrast" => {
            "id" => "idempotency-key-vs-unique-index",
            "title" => "Idempotency Key vs Unique Index",
            "path" => "decision-contrasts/05-idempotency-key-vs-unique-index.md"
          },
          "simulations" => [ "rate-limit-vs-load-shedding" ]
        }
      ]
    }
  end
end

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

  test "imports backend principle cards as library documents" do
    source = FakeSource.new([
      {
        kind: "backend_principle",
        source_path: "areas/09-backend-principles/cards/http-protocol.md",
        body_markdown: "# HTTP Protocol\n\nContrato base de APIs."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :backend_principle?
    assert_equal "http-protocol", document.slug
    assert_equal "HTTP Protocol", document.title
  end

  test "imports engineering case study cards as library documents" do
    source = FakeSource.new([
      {
        kind: "engineering_case_study",
        source_path: "areas/10-engineering-case-studies/cards/production-migrations-backfills.md",
        body_markdown: "# Production Migrations and Backfills\n\nMigracoes incrementais em producao."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :engineering_case_study?
    assert_equal "production-migrations-backfills", document.slug
    assert_equal "Production Migrations and Backfills", document.title
  end

  test "imports operational playbooks as library documents" do
    source = FakeSource.new([
      {
        kind: "operational_playbook",
        source_path: "areas/11-operational-playbooks/playbooks/incident-severity-and-triage.md",
        body_markdown: "# Incident Severity and Triage\n\nPrimeiros minutos de incidente."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :operational_playbook?
    assert_equal "incident-severity-and-triage", document.slug
    assert_equal "Incident Severity and Triage", document.title
  end

  test "imports engineering practice cards as library documents" do
    source = FakeSource.new([
      {
        kind: "engineering_practice",
        source_path: "areas/12-engineering-practice/cards/data-contracts-and-schema-evolution.md",
        body_markdown: "# Data Contracts and Schema Evolution\n\nContrato de dados executavel."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :engineering_practice?
    assert_equal "data-contracts-and-schema-evolution", document.slug
    assert_equal "Data Contracts and Schema Evolution", document.title
  end

  test "imports interview story bank documents as library documents" do
    source = FakeSource.new([
      {
        kind: "interview_story_bank",
        source_path: "interview/story-bank/01-ruby-rails-backend-story-bank.md",
        body_markdown: "# Ruby and Rails Backend Story Bank\n\nInterview narrative."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :interview_story_bank?
    assert_equal "01-ruby-rails-backend-story-bank", document.slug
    assert_equal "Ruby and Rails Backend Story Bank", document.title
    assert_equal 1, document.position
  end

  test "imports reference documents as library documents" do
    source = FakeSource.new([
      {
        kind: "reference_document",
        source_path: "areas/01-metodo-e-entrevistas/notes.md",
        body_markdown: "# Notes\n\nResumo de entrevista."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :reference_document?
    assert_equal "areas-01-metodo-e-entrevistas-notes", document.slug
    assert_equal "Notes", document.title
  end

  test "imports backend principle labs as library documents" do
    source = FakeSource.new([
      {
        kind: "backend_lab",
        source_path: "areas/13-backend-principle-labs/labs/build-an-idempotent-write-api.md",
        body_markdown: "# Build an Idempotent Write API\n\nExercicio de write path."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :backend_lab?
    assert_equal "build-an-idempotent-write-api", document.slug
    assert_equal "Build an Idempotent Write API", document.title
  end

  test "imports engineering case study labs as library documents" do
    source = FakeSource.new([
      {
        kind: "engineering_case_lab",
        source_path: "areas/14-engineering-case-study-labs/labs/plan-a-zero-downtime-migration.md",
        body_markdown: "# Plan a Zero-Downtime Migration\n\nExercicio de migracao."
      }
    ], nil)

    document = Content::Importer.new(source: source).call.first

    assert_predicate document, :engineering_case_lab?
    assert_equal "plan-a-zero-downtime-migration", document.slug
    assert_equal "Plan a Zero-Downtime Migration", document.title
  end

  test "imports side track documents and enriches them from curriculum" do
    source = FakeSource.new([
      {
        kind: "side_track_overview",
        source_path: "areas/08-sistemas-ia/llm-foundations/README.md",
        body_markdown: "# LLM Foundations\n\nBuilder-heavy track."
      },
      {
        kind: "side_track_chapter",
        source_path: "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md",
        body_markdown: "# Tokens, Embeddings and Training Windows\n\n## First Principles Learning Pass\n\nCheckpoint builder."
      },
      {
        kind: "side_track_review_card",
        source_path: "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md",
        body_markdown: "# Tokens Recall\n\n## Recall\n\n- `Pergunta`: tokenizacao e embedding sao a mesma coisa?\n- `Resposta curta`: nao."
      }
    ], curriculum)

    imported = Content::Importer.new(source: source).call
    overview = imported.detect(&:side_track_overview?)
    chapter = imported.detect(&:side_track_chapter?)
    review_card = imported.detect(&:side_track_review_card?)

    assert_equal "llm-foundations", overview.slug
    assert_equal 1, overview.metadata.fetch("chapter_count")
    assert_equal "llm-foundations-01-tokens-embeddings-and-training-windows", chapter.slug
    assert_equal 1, chapter.position
    assert_equal "LLM Foundations", chapter.metadata.fetch("side_track_title")
    assert_equal "1/1", chapter.metadata.fetch("study_order")
    assert_equal "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md", chapter.metadata.fetch("review_card_path")
    assert_equal "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md", review_card.metadata.fetch("chapter_path")
  end

  private

  def curriculum
    {
      "phases" => [
        { "id" => "fase-1", "title" => "Fase 1 - Base forte" }
      ],
      "areas" => [
        { "id" => "03-filas-e-consistencia", "title" => "Filas e Consistencia" },
        { "id" => "08-sistemas-ia", "title" => "Sistemas de IA" }
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
      ],
      "side_tracks" => [
        {
          "id" => "llm-foundations",
          "title" => "LLM Foundations",
          "area_id" => "08-sistemas-ia",
          "path" => "areas/08-sistemas-ia/llm-foundations/README.md",
          "source_map" => "areas/08-sistemas-ia/llm-foundations/source-map.md",
          "reviews_readme" => "areas/08-sistemas-ia/llm-foundations/reviews/README.md",
          "chapters" => [
            {
              "number" => 1,
              "title" => "Tokens, Embeddings and Training Windows",
              "path" => "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md",
              "review_card" => "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md",
              "upstream" => [
                "https://github.com/rasbt/LLMs-from-scratch/blob/main/ch02/01_main-chapter-code/ch02.ipynb"
              ],
              "bridge_topics" => [ "areas/08-sistemas-ia/topics/token-cost.md" ],
              "bridge_cases" => [ "real-world-cases/05-product-scenarios/chatgpt-llm-product/README.md" ]
            }
          ]
        }
      ]
    }
  end
end

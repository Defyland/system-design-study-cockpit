require "test_helper"

class CurriculumGraphTest < ActiveSupport::TestCase
  test "resolves chapter metadata from curriculum manifest" do
    graph = CurriculumGraph.new(curriculum)

    metadata = graph.metadata_for(
      kind: "chapter",
      source_path: "chapters/chapter-03-idempotent-writes.md",
      slug: "chapter-03-idempotent-writes"
    )

    assert_equal 3, metadata.fetch("chapter_number")
    assert_equal "3/1", metadata.fetch("study_order")
    assert_equal "Fase 1 - Base forte", metadata.fetch("phase_title")
    assert_equal "Filas e Consistencia", metadata.fetch("primary_area_title")
    assert_equal "Stripe - Idempotent Payments", metadata.fetch("primary_case_title")
    assert_equal "labs/chapters/chapter-03-idempotent-writes.md", metadata.fetch("lab_path")
    assert_equal [ "rate-limit-vs-load-shedding" ], metadata.fetch("simulations")
  end

  test "maps dependent documents back to their chapter" do
    graph = CurriculumGraph.new(curriculum)

    lab_metadata = graph.metadata_for(
      kind: "lab",
      source_path: "labs/chapters/chapter-03-idempotent-writes.md",
      slug: "chapter-03-idempotent-writes"
    )
    case_metadata = graph.metadata_for(
      kind: "real_world_case",
      source_path: "real-world-cases/stripe/README.md",
      slug: "stripe-idempotent-payments"
    )
    simulation_metadata = graph.metadata_for(
      kind: "simulation_lab",
      source_path: "simulation-labs/rate-limit-vs-load-shedding.md",
      slug: "rate-limit-vs-load-shedding"
    )

    assert_equal "chapter-03-idempotent-writes", lab_metadata.fetch("chapter_slug")
    assert_equal "primary", case_metadata.fetch("used_by_chapters").first.fetch("role")
    assert_equal "chapter-03-idempotent-writes", simulation_metadata.fetch("used_by_chapters").first.fetch("slug")
  end

  test "resolves side track metadata from curriculum manifest" do
    graph = CurriculumGraph.new(curriculum)

    overview_metadata = graph.metadata_for(
      kind: "side_track_overview",
      source_path: "areas/08-sistemas-ia/llm-foundations/README.md",
      slug: "llm-foundations"
    )
    chapter_metadata = graph.metadata_for(
      kind: "side_track_chapter",
      source_path: "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md",
      slug: "llm-foundations-01-tokens-embeddings-and-training-windows"
    )
    review_metadata = graph.metadata_for(
      kind: "side_track_review_card",
      source_path: "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md",
      slug: "llm-foundations-01-tokens-embeddings-and-training-windows"
    )
    reference_metadata = graph.metadata_for(
      kind: "side_track_reference",
      source_path: "areas/08-sistemas-ia/llm-foundations/source-map.md",
      slug: "llm-foundations-source-map"
    )

    assert_equal "LLM Foundations", overview_metadata.fetch("side_track_title")
    assert_equal 1, overview_metadata.fetch("chapter_count")
    assert_equal "1/1", chapter_metadata.fetch("study_order")
    assert_equal "areas/08-sistemas-ia/llm-foundations/reviews/cards/01-tokens-embeddings-and-training-windows.md", chapter_metadata.fetch("review_card_path")
    assert_equal "areas/08-sistemas-ia/topics/token-cost.md", chapter_metadata.fetch("bridge_topics").first
    assert_equal "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md", review_metadata.fetch("chapter_path")
    assert_equal "source_map", reference_metadata.fetch("reference_kind")
  end

  test "lists side track documents derived from the curriculum manifest" do
    specs = CurriculumGraph.side_track_document_specs(curriculum)

    assert_includes specs, {
      kind: "side_track_overview",
      source_path: "areas/08-sistemas-ia/llm-foundations/README.md"
    }
    assert_includes specs, {
      kind: "side_track_reference",
      source_path: "areas/08-sistemas-ia/llm-foundations/source-map.md"
    }
    assert_includes specs, {
      kind: "side_track_chapter",
      source_path: "areas/08-sistemas-ia/llm-foundations/chapters/01-tokens-embeddings-and-training-windows.md"
    }
  end

  private

  def curriculum
    {
      "phases" => [
        { "id" => "fase-1", "title" => "Fase 1 - Base forte" }
      ],
      "areas" => [
        {
          "id" => "03-filas-e-consistencia",
          "title" => "Filas e Consistencia",
          "content_dirs" => { "notes" => "areas/03-filas-e-consistencia/notes.md" }
        },
        {
          "id" => "08-sistemas-ia",
          "title" => "Sistemas de IA",
          "content_dirs" => { "notes" => "areas/08-sistemas-ia/notes.md" }
        }
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

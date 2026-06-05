require "test_helper"

class ChapterStudyContextTest < ActiveSupport::TestCase
  setup do
    StudyDocument.destroy_all
  end

  test "resolves related imported documents for a chapter" do
    chapter = create_document(
      kind: "chapter",
      slug: "chapter-03-idempotent-writes",
      source_path: "chapters/chapter-03-idempotent-writes.md"
    )
    lab = create_document(
      kind: "lab",
      slug: "chapter-03-idempotent-writes",
      title: "Lab 03",
      source_path: "labs/chapters/chapter-03-idempotent-writes.md"
    )
    review_card = create_document(
      kind: "review_card",
      slug: "03-idempotent-writes",
      title: "Review 03",
      source_path: "reviews/cards/03-idempotent-writes.md"
    )
    use_case = create_document(
      kind: "real_world_case",
      slug: "stripe-idempotent-payments",
      title: "Stripe - Idempotent Payments",
      source_path: "real-world-cases/stripe/README.md"
    )

    context = ChapterStudyContext.new(chapter, graph: CurriculumGraph.new(curriculum))

    assert_predicate context, :available?
    assert_equal "3/1", context.study_order
    assert_equal "Fase 1 - Base forte", context.phase_title
    assert_equal "Filas e Consistencia", context.primary_area.title
    assert_equal lab, context.lab.document
    assert_equal review_card, context.review_card.document
    assert_equal use_case, context.primary_case.document
  end

  test "falls back to imported metadata when curriculum cache is cold" do
    chapter = create_document(
      kind: "chapter",
      slug: "chapter-03-idempotent-writes",
      source_path: "chapters/chapter-03-idempotent-writes.md"
    )
    lab = create_document(
      kind: "lab",
      slug: "chapter-03-idempotent-writes",
      title: "Lab 03",
      source_path: "labs/chapters/chapter-03-idempotent-writes.md"
    )
    chapter.update!(
      phase: "Fase 1 - Base forte",
      metadata: {
        "curriculum_id" => "idempotent-writes-under-ambiguous-failure",
        "chapter_number" => 3,
        "chapter_slug" => "chapter-03-idempotent-writes",
        "study_order" => "3/14",
        "phase_id" => "fase-1",
        "phase_title" => "Fase 1 - Base forte",
        "primary_area_id" => "03-filas-e-consistencia",
        "primary_area_title" => "Filas e Consistencia",
        "secondary_area_ids" => [],
        "notes_paths" => [ "areas/03-filas-e-consistencia/notes.md" ],
        "primary_case_id" => "stripe-idempotent-payments",
        "primary_case_title" => "Stripe - Idempotent Payments",
        "primary_case_path" => "real-world-cases/stripe/README.md",
        "complementary_cases" => [],
        "lab_path" => "labs/chapters/chapter-03-idempotent-writes.md",
        "review_card_path" => "reviews/cards/03-idempotent-writes.md",
        "simulations" => []
      }
    )

    context = ChapterStudyContext.new(chapter, graph: CurriculumGraph.new({}))

    assert_predicate context, :available?
    assert_equal "3/14", context.study_order
    assert_equal "Filas e Consistencia", context.primary_area.title
    assert_equal lab, context.lab.document
  end

  private

  def create_document(kind:, slug:, source_path:, title: "Chapter 03")
    StudyDocument.create!(
      kind: kind,
      slug: slug,
      title: title,
      source_path: source_path,
      position: 3,
      body_markdown: "# #{title}",
      body_checksum: "#{kind}-#{slug}"
    )
  end

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
      ]
    }
  end
end

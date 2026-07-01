require "test_helper"

class InterviewStudyPlanTest < ActiveSupport::TestCase
  setup do
    reset_study_tables!
  end

  test "builds a 14 day plan from persisted cockpit content" do
    create_document(
      kind: "side_track_overview",
      slug: "backend-interview-foundations",
      title: "Backend Interview Foundations",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/README.md"
    )
    create_document(
      kind: "side_track_chapter",
      slug: "backend-interview-foundations-01-dsa-operating-system-and-pattern-selection",
      title: "DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/01-dsa-operating-system-and-pattern-selection.md"
    )
    create_document(
      kind: "side_track_review_card",
      slug: "backend-interview-foundations-01-dsa-operating-system-and-pattern-selection",
      title: "Review Card 01 - DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/reviews/cards/01-dsa-operating-system-and-pattern-selection.md"
    )
    create_document(
      kind: "side_track_chapter",
      slug: "backend-interview-foundations-05-ruby-on-rails-interview-surface-area",
      title: "Ruby on Rails Interview Surface Area",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/05-ruby-on-rails-interview-surface-area.md"
    )
    create_document(
      kind: "side_track_chapter",
      slug: "backend-interview-foundations-06-javascript-and-typescript-interview-surface-area",
      title: "JavaScript and TypeScript Interview Surface Area",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/06-javascript-and-typescript-interview-surface-area.md"
    )
    create_document(
      kind: "side_track_reference",
      slug: "backend-interview-foundations-source-map",
      title: "Backend Interview Foundations Source Map",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/source-map.md"
    )
    create_document(
      kind: "interview_story_bank",
      slug: "03-ruby-rails-senior-question-bank",
      title: "Ruby / Rails Senior Question Bank",
      source_path: "interview/story-bank/03-ruby-rails-senior-question-bank.md"
    )
    create_document(
      kind: "reference_document",
      slug: "areas-01-metodo-e-entrevistas-snippets-system-design-interview-checklist",
      title: "System Design Interview Checklist",
      source_path: "areas/01-metodo-e-entrevistas/snippets/system-design-interview-checklist.md"
    )

    plan = InterviewStudyPlan.new.call

    assert_equal 14, plan.days.size
    assert_equal "Dia 01", plan.days.first.label
    assert_includes plan.days.first.documents.map(&:title), "DSA Operating System and Pattern Selection"
    assert_includes plan.days.first.documents.map(&:title), "Review Card 01 - DSA Operating System and Pattern Selection"
    assert_includes plan.days.map(&:focus), "Rails interview surface"
    assert_includes plan.days.flat_map { |day| day.documents.map(&:title) }, "Backend Interview Foundations Source Map"
  end

  test "loads documents and checkpoints without per-reference query fan-out" do
    chapter = create_document(
      kind: "side_track_chapter",
      slug: "backend-interview-foundations-01-dsa-operating-system-and-pattern-selection",
      title: "DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/01-dsa-operating-system-and-pattern-selection.md"
    )
    review = create_document(
      kind: "side_track_review_card",
      slug: "backend-interview-foundations-01-dsa-operating-system-and-pattern-selection",
      title: "Review Card 01 - DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/reviews/cards/01-dsa-operating-system-and-pattern-selection.md"
    )
    reference = create_document(
      kind: "reference_document",
      slug: "areas-01-metodo-e-entrevistas-snippets-system-design-interview-checklist",
      title: "System Design Interview Checklist",
      source_path: "areas/01-metodo-e-entrevistas/snippets/system-design-interview-checklist.md"
    )

    create_checkpoint(chapter, 1, "Escolha o padrao certo antes de codar.")
    create_checkpoint(chapter, 2, "Explique o trade-off do HashMap.")
    create_checkpoint(review, 1, "Recite o loop de entrevista.")
    create_checkpoint(reference, 1, "Liste o checklist de system design.")

    queries = count_queries { @plan = InterviewStudyPlan.new.call }

    assert_operator queries, :<=, 4
    assert_equal [
      "Escolha o padrao certo antes de codar.",
      "Explique o trade-off do HashMap.",
      "Recite o loop de entrevista.",
      "Liste o checklist de system design."
    ], @plan.days.first.checkpoints
  end

  private

  def create_document(kind:, slug:, title:, source_path:)
    StudyDocument.create!(
      kind: kind,
      slug: slug,
      title: title,
      source_path: source_path,
      position: 1,
      body_markdown: "# #{title}",
      body_checksum: slug
    )
  end

  def create_checkpoint(document, position, prompt)
    document.checkpoints.create!(
      position: position,
      source_label: "Checkpoint #{position}",
      prompt: prompt,
      good_answer: "Resposta #{position}"
    )
  end
end

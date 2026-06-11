require "test_helper"

class LearningRecordTest < ActiveSupport::TestCase
  test "allows a learning record tied to a chapter from the same side track" do
    overview = create_document(kind: "side_track_overview", slug: "llm-foundations", side_track_id: "llm-foundations")
    chapter = create_document(kind: "side_track_chapter", slug: "llm-foundations-01-tokens", side_track_id: "llm-foundations")

    record = LearningRecord.new(
      study_document: overview,
      related_document: chapter,
      cue: "Attention nao e contexto bruto.",
      insight: "Ficou claro por que o custo cresce antes mesmo de servir o token.",
      unlocks: "Consigo discutir latencia de inferencia."
    )

    assert_predicate record, :valid?
  end

  test "rejects a related document from another side track" do
    overview = create_document(kind: "side_track_overview", slug: "llm-foundations", side_track_id: "llm-foundations")
    other_track_chapter = create_document(kind: "side_track_chapter", slug: "ml-systems-01", side_track_id: "ml-systems")

    record = LearningRecord.new(
      study_document: overview,
      related_document: other_track_chapter,
      cue: "Cue",
      insight: "Insight"
    )

    assert_not record.valid?
    assert_includes record.errors[:related_document], "must belong to the same side track"
  end

  private

  def create_document(kind:, slug:, side_track_id:)
    StudyDocument.create!(
      kind: kind,
      slug: slug,
      title: slug.tr("-", " ").titleize,
      source_path: "tmp/#{kind}/#{slug}.md",
      position: 0,
      body_markdown: "# #{slug.tr('-', ' ').titleize}",
      body_checksum: SecureRandom.hex,
      metadata: { "side_track_id" => side_track_id }
    )
  end
end

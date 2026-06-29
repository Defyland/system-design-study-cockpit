require "test_helper"

class StudyMissionTest < ActiveSupport::TestCase
  test "allows a mission only for a side track overview" do
    mission = StudyMission.new(
      study_document: create_document(kind: "side_track_overview", slug: "llm-foundations"),
      why_now: "Quero fundamento de modelo para falar menos besteira sobre sistemas de IA.",
      success_signal: "Consigo comparar finetuning, RAG e serving sem resposta generica."
    )

    assert_predicate mission, :valid?
  end

  test "rejects missions anchored to non side track documents" do
    mission = StudyMission.new(
      study_document: create_document(kind: "chapter", slug: "chapter-01-relational-scaling"),
      why_now: "Quero revisar.",
      success_signal: "Lembro o chapter."
    )

    assert_not mission.valid?
    assert_includes mission.errors[:study_document], "must be a side track overview"
  end

  private

  def create_document(kind:, slug:)
    unique_slug = "#{slug}-#{SecureRandom.hex(4)}"

    StudyDocument.create!(
      kind: kind,
      slug: unique_slug,
      title: slug.tr("-", " ").titleize,
      source_path: "tmp/#{kind}/#{unique_slug}.md",
      position: 0,
      body_markdown: "# #{slug.tr('-', ' ').titleize}",
      body_checksum: SecureRandom.hex,
      metadata: { "side_track_id" => "llm-foundations" }
    )
  end
end

require "application_system_test_case"

class StudyFlowTest < ApplicationSystemTestCase
  setup do
    Reminder.delete_all
    StudyDocument.destroy_all
  end

  test "student opens a chapter and reveals checkpoint feedback" do
    document = StudyDocument.create!(
      kind: "chapter",
      slug: "chapter-01-test",
      title: "Chapter 01 - Test",
      source_path: "chapters/chapter-01-test.md",
      position: 1,
      body_markdown: "# Chapter 01 - Test",
      body_checksum: "abc"
    )
    document.create_study_progress!
    document.study_blocks.create!(position: 1, kind: "paragraph", content_markdown: "Um paragrafo de estudo.")
    document.study_blocks.create!(position: 2, kind: "paragraph", content_markdown: "Outro paragrafo.")
    document.study_blocks.create!(position: 3, kind: "paragraph", content_markdown: "Terceiro paragrafo.")
    document.checkpoints.create!(
      position: 1,
      source_label: "Fixacao",
      prompt: "Qual requisito vem primeiro?",
      good_answer: "O requisito real.",
      bad_answer: "A ferramenta.",
      correction: "Questione antes de escolher."
    )

    visit root_path
    click_link "Abrir chapter"
    find("summary", text: "Revelar resposta e correcao").click

    assert_text "O requisito real."
    assert_text "A ferramenta."
  end
end

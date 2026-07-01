require "test_helper"

class LibraryControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_study_tables!
  end

  test "renders interview story bank with narrative and side question column" do
    story_bank = StudyDocument.create!(
      kind: "interview_story_bank",
      slug: "04-backend-voice-call-narrative",
      title: "Narrativa Final - Backend Ruby / Rails",
      source_path: "interview/story-bank/04-backend-voice-call-narrative.md",
      position: 4,
      body_markdown: <<~MARKDOWN,
        # Narrativa Final - Backend Ruby / Rails

        ## Abertura

        Tenho uma narrativa principal.

        ## Q&A de Reserva - Follow-ups Tecnicos

        > Use so quando o entrevistador cavar.

        ### 1. Locking otimista vs pessimista

        **Q: Como voce escolhe entre lock otimista e pessimista?**

        Pessimista segura a linha. Otimista detecta conflito no commit.
      MARKDOWN
      body_checksum: "story-bank-layout"
    )
    story_bank.study_blocks.create!(
      position: 1,
      kind: "heading",
      content_markdown: "# Narrativa Final - Backend Ruby / Rails"
    )

    get library_document_path(kind: story_bank.kind, slug: story_bank.slug)

    assert_response :success
    assert_equal 1, response.body.scan("Narrativa Final - Backend Ruby / Rails").size
    assert_includes response.body, "story-bank-reader"
    assert_includes response.body, "Perguntas laterais"
    assert_includes response.body, "<details id=\"story-bank-question-1\""
    assert_no_match(/<details[^>]+open/, response.body)
    assert_includes response.body, "Como voce escolhe entre lock otimista e pessimista?"
    assert_includes response.body, "Pessimista segura a linha. Otimista detecta conflito no commit."
  end
end

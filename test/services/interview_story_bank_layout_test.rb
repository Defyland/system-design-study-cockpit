require "test_helper"

class InterviewStoryBankLayoutTest < ActiveSupport::TestCase
  test "splits narrative and follow-up questions from story bank markdown" do
    document = StudyDocument.new(
      kind: "interview_story_bank",
      title: "Narrativa Final - Backend Ruby / Rails",
      body_markdown: <<~MARKDOWN
        # Narrativa Final - Backend Ruby / Rails

        > Leia com pausas.

        ## Abertura

        Tenho uma narrativa principal.

        ## Q&A de Reserva - Follow-ups Tecnicos

        > Use so quando cavar.

        ### 1. Locking otimista vs pessimista

        **Q: Como voce escolhe entre lock otimista e pessimista numa operacao financeira?**

        Resposta da primeira pergunta.

        ### 2. Migration em escala

        Resposta da segunda pergunta.
      MARKDOWN
    )

    layout = InterviewStoryBankLayout.new(document: document)

    assert_predicate layout, :available?
    refute_includes layout.narrative_markdown, "# Narrativa Final - Backend Ruby / Rails"
    assert_includes layout.narrative_markdown, "## Abertura"
    assert_includes layout.qa_intro_markdown, "Use so quando cavar."
    assert_equal 2, layout.questions.size
    assert_equal "Como voce escolhe entre lock otimista e pessimista numa operacao financeira?", layout.questions.first.prompt
    assert_equal "story-bank-question-1", layout.questions.first.anchor
    refute_includes layout.questions.first.answer_markdown, "**Q:"
    assert_includes layout.questions.first.answer_markdown, "Resposta da primeira pergunta."
  end
end

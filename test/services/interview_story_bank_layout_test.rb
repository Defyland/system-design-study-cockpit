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

        ### 14. Experiencia com Kafka

        **Q: Qual foi sua experiencia com Kafka?**

        Resposta sobre curriculo.

        ### 32. Blocks, Proc e lambda

        Como voce explica blocks, procs e lambdas em Ruby?

        ### 12. Fat model vs service object

        Rails nao recomenda fat model?

        ### 1. Locking otimista vs pessimista

        Como voce escolhe entre lock otimista e pessimista numa operacao financeira?

        ### 79. SQL Injection

        Como evitar SQL Injection em Rails?
      MARKDOWN
    )

    layout = InterviewStoryBankLayout.new(document: document)

    assert_predicate layout, :available?
    refute_includes layout.narrative_markdown, "# Narrativa Final - Backend Ruby / Rails"
    assert_includes layout.narrative_markdown, "## Abertura"
    assert_includes layout.qa_intro_markdown, "Use so quando cavar."
    assert_equal 5, layout.questions.size
    assert_equal "Qual foi sua experiencia com Kafka?", layout.questions.first.prompt
    assert_equal "story-bank-question-1", layout.questions.first.anchor
    assert_equal "resume", layout.questions.first.area_key
    refute_includes layout.questions.first.answer_markdown, "**Q:"
    assert_includes layout.questions.first.answer_markdown, "Resposta sobre curriculo."
    assert_equal "rails", layout.questions.last.area_key
    assert_equal [ "resume", "ruby", "rails", "performance" ], layout.question_groups.map(&:key)
    assert_equal [ "Meu curriculo", "Ruby", "Ruby on Rails", "Performance" ], layout.question_groups.map(&:label)
    assert_equal [ 1, 1, 2, 1 ], layout.question_groups.map { |group| group.questions.size }
  end
end

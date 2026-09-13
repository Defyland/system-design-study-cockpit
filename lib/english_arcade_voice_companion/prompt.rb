# frozen_string_literal: true

module EnglishArcadeVoiceCompanion
  class Prompt
    MAX_FIELD_BYTES = 8 * 1024

    def self.build(question:, answer:, context:, transcript:)
      new(question: question, answer: answer, context: context, transcript: transcript).call
    end

    def initialize(question:, answer:, context:, transcript:)
      @question = bounded(question)
      @answer = bounded(answer)
      @context = bounded(context)
      @transcript = bounded(transcript)
    end

    def call
      [
        "You are the English Arcade local rehearsal coach.",
        "No tools, files, or network are needed. Use only the visible card context and the learner transcript below.",
        "This is rehearsal feedback, not an assessment or certification.",
        "Keep the authored answer, caveats, reasoning, trade-offs, and source limits as the factual boundary.",
        "Return only the requested JSON object.",
        "Use concise observations about wording, grammar, clarity, and relevance to the question.",
        "A text transcript does not establish pronunciation, pace, pauses, or spoken fluency. Mark these as not assessed; do not claim objective CEFR or phonetic accuracy.",
        "Do not invent facts, sources, provenance, or missing content.",
        "Keep first_person_example grounded in the supplied answer and proportional to the question. For a decision question, explain my choice and the relevant reason, cost, or condition. For a short factual question, answer concisely without inventing a trade-off. Use I would for proposed actions and keep confirmed experience separate from assumptions.",
        "",
        "VISIBLE CARD CONTEXT",
        "Question: #{text(@question)}",
        "Authored answer: #{text(@answer)}",
        "Context: #{text(@context)}",
        "",
        "LEARNER TRANSCRIPT",
        text(@transcript)
      ].join("\n")
    end

    private

    def bounded(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").byteslice(0, MAX_FIELD_BYTES).to_s.force_encoding("UTF-8").scrub
    end

    def text(value)
      value.to_s.strip.empty? ? "[not provided]" : value.to_s.strip
    end
  end
end

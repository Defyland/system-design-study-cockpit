require "test_helper"
require "english_arcade_voice_companion"

class EnglishArcadeVoiceCompanionPromptTest < ActiveSupport::TestCase
  test "keeps analysis bounded to visible context and states safety limits" do
    prompt = EnglishArcadeVoiceCompanion::Prompt.build(
      question: "How would you protect it?",
      answer: "I would verify the boundary.",
      context: "Authored context",
      transcript: "I would verify the boundary."
    )
    assert_includes prompt, "No tools, files, or network are needed"
    assert_includes prompt, "Authored answer: I would verify the boundary."
    assert_includes prompt, "LEARNER TRANSCRIPT"
    assert_includes prompt, "A text transcript does not establish pronunciation, pace, pauses, or spoken fluency"
    assert_includes prompt, "Mark these as not assessed"
    assert_includes prompt, "keep confirmed experience separate from assumptions"
    assert_includes prompt, "Do not invent facts, sources, provenance"
    refute_includes prompt, "auth.json"
  end

  test "caps a multibyte field by bytes" do
    prompt = EnglishArcadeVoiceCompanion::Prompt.new(
      question: "é" * 10_000,
      answer: "Answer",
      context: "Context",
      transcript: "Transcript"
    ).call
    question_line = prompt.lines.find { |line| line.start_with?("Question:") }
    assert_operator question_line.bytesize, :<=, EnglishArcadeVoiceCompanion::Prompt::MAX_FIELD_BYTES + 12
  end

  test "a short factual rehearsal does not require an invented tradeoff" do
    prompt = EnglishArcadeVoiceCompanion::Prompt.build(
      question: "What does the key identify?",
      answer: "I use it to identify the payment intent.",
      context: "Give a one-sentence factual answer.",
      transcript: "I use the key for that payment intent."
    )

    assert_includes prompt, "For a short factual question, answer concisely without inventing a trade-off."
    assert_includes prompt, "proportional to the question"
    assert_includes prompt, "Authored answer: I use it to identify the payment intent."
  end
end

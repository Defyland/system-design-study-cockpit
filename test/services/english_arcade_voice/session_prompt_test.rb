require "test_helper"

class EnglishArcadeVoiceSessionPromptTest < ActiveSupport::TestCase
  setup do
    @builder = EnglishArcadeSessionBuilder.new
    @card = @builder.card_for(
      target: "salesforce",
      card_key: "salesforce-01-bulkification",
      session: nil
    )
  end

  test "uses only authoritative card material and states the coaching limits" do
    prompt = EnglishArcadeVoice::SessionPrompt.for(@card)

    assert_includes prompt, @card.prompt
    assert_includes prompt, @card.answer_text
    assert_includes prompt, "answered-question rehearsal"
    assert_includes prompt, "first-person safe interview language"
    assert_includes prompt, "clarity, fluency, pace, grammar, and relevance"
    assert_includes prompt, "objective CEFR scoring"
    assert_includes prompt, "guaranteed pronunciation or phonetic result"
    assert_includes prompt, "visible card sources"
    refute_includes prompt, "correct_choice"
    refute_includes prompt, "client-authored"
  end

  test "does not invent absent card content" do
    card = Struct.new(:prompt, :context, :answer_text).new("Question", "Context", "Answer")
    prompt = EnglishArcadeVoice::SessionPrompt.for(card)

    assert_includes prompt, "No source limit was provided; use only the visible card material."
    assert_includes prompt, "No additional authored reasoning or trade-off was provided"
    refute_includes prompt, "invented source"
  end

  test "keeps only minimal source limits and omits paths, repositories, and commits" do
    card = Struct.new(:prompt, :context, :answer_text, :sources, :provenance).new(
      "Question",
      "Context",
      "Answer",
      [ { "repo" => "private-repo", "path" => "/Users/secret/answer.md", "commit" => "sensitive-commit" } ],
      {
        "evidence_class" => "repository-backed",
        "confirmation_required" => [ "Confirm the operational limit before claiming it." ],
        "confidentiality" => { "level" => "private", "note" => "Do not mention this internal launch path." },
        "files" => [ { "path" => "/Users/secret/answer.md", "commit" => "sensitive-commit" } ],
        "repository" => "private-repo"
      }
    )

    prompt = EnglishArcadeVoice::SessionPrompt.for(card)

    assert_includes prompt, "Confirmation required: Confirm the operational limit before claiming it."
    assert_includes prompt, "Evidence class: repository-backed"
    assert_includes prompt, "Confidentiality level: private"
    assert_includes prompt, "Visible authored source pointers exist (count: 1)."
    refute_includes prompt, "/Users/secret/answer.md"
    refute_includes prompt, "private-repo"
    refute_includes prompt, "sensitive-commit"
    refute_includes prompt, "internal launch path"
  end
end

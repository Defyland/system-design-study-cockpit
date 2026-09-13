require "test_helper"

class EnglishArcadeBestAnswerFillTest < ActiveSupport::TestCase
  setup do
    @builder = EnglishArcadeSessionBuilder.new
  end

  test "fills the authored answer and a complete false-equivalence ledger" do
    card = @builder.card_for(target: "rails", card_key: "rails-01-n-plus-one")
    fill = EnglishArcadeBestAnswerFill.call(card)
    artifact = EnglishArcadeAttemptContract.artifact_from(fill, critical_thinking: card.critical_thinking)

    assert_equal card.correct_choice, fill.fetch("answer_choice")
    assert_equal card.answer_text, fill.fetch("typed_answer")
    assert_equal card.critical_thinking.dig("claim_map", "fact"), fill.fetch("evidence_verified")
    assert_equal card.critical_thinking.dig("comparison", "hard_constraint"), fill.fetch("comparison_hard_constraint")
    refute fill.key?("english_directness")
    refute fill.key?("confidence_percent")
    refute fill.keys.any? { |key| key.start_with?("self_") }
    assert_equal [ "confidence_percent" ], artifact.fetch("missing")
    assert EnglishArcadeBestAnswerFill.available_for?(card)
  end

  test "fills both authored alternatives when a real comparison applies" do
    card = @builder.card_for(target: "career", card_key: "career-01-a-60-to-90-second-introduction")
    fill = EnglishArcadeBestAnswerFill.call(card)
    artifact = EnglishArcadeAttemptContract.artifact_from(fill.merge("confidence_percent" => 70), critical_thinking: card.critical_thinking)

    assert_includes fill.fetch("comparison_option_a"), "Rails professional narrative"
    assert_includes fill.fetch("comparison_option_b"), "portfolio example"
    assert_includes fill.fetch("comparison_tradeoff"), "I would compare these consequences before choosing."
    assert_includes fill.fetch("comparison_tradeoff"), card.critical_thinking.dig("comparison", "alternatives", 0, "cost_or_risk")
    assert artifact.fetch("complete"), artifact.fetch("missing").inspect
  end

  test "does not claim a complete authored fill for a stripped adaptive variant" do
    card = @builder.card_for(target: "rails", card_key: "rails-01-n-plus-one", variant_id: "follow_up")

    refute EnglishArcadeBestAnswerFill.available_for?(card)
  end

  test "tradeoff paragraphs preserve authored punctuation and separate both alternatives" do
    card = @builder.card_for(target: "career", card_key: "career-01-a-60-to-90-second-introduction")
    card.critical_thinking["comparison"]["alternatives"] = [
      { "option" => "A", "benefit" => "I can recover the event.", "cost_or_risk" => "I must operate the relay" },
      { "option" => "B", "benefit" => "I keep fewer components", "cost_or_risk" => "I still need reconciliation." }
    ]

    assert_equal <<~TEXT.strip, EnglishArcadeBestAnswerFill.call(card).fetch("comparison_tradeoff")
      I would compare these consequences before choosing.

      Option A
      Benefit: I can recover the event.
      Cost or risk: I must operate the relay

      Option B
      Benefit: I keep fewer components
      Cost or risk: I still need reconciliation.
    TEXT
  end
end

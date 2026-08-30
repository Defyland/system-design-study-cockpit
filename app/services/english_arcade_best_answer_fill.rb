class EnglishArcadeBestAnswerFill
  def self.call(card)
    new(card).call
  end

  def self.available_for?(card)
    # Confidence is learner evidence and must never be synthesized. A bounded
    # validation-only value lets this predicate check whether every authored
    # field exists without returning or persisting fabricated calibration.
    candidate = call(card).merge("confidence_percent" => 50)
    EnglishArcadeAttemptContract.artifact_from(candidate, critical_thinking: card.critical_thinking).fetch("complete")
  end

  def initialize(card)
    @card = card
    @critical = card.critical_thinking.to_h.deep_stringify_keys
  end

  def call
    {
      "answer_choice" => @card.correct_choice,
      "typed_answer" => @card.answer_text,
      "problem_frame" => @critical["problem_frame"],
      "evidence_verified" => claim("fact"),
      "evidence_inference" => claim("inference"),
      "evidence_assumption" => claim("assumption"),
      "evidence_gap" => claim("unknown"),
      "source_quality" => source_quality,
      **comparison_values,
      "counterexample" => @critical.dig("failure_probe", "prompt"),
      "change_my_mind" => @critical.dig("certainty", "update_trigger")
    }.compact
  end

  private

  def claim(kind)
    @critical.dig("claim_map", kind)
  end

  def source_quality
    check = @critical.fetch("evidence_check", {})
    [ check["basis"], check["limitation"] ].compact_blank.join(" Limitation: ")
  end

  def comparison_values
    comparison = @critical.fetch("comparison", {})
    if comparison["applicable"] == true
      alternatives = Array(comparison["alternatives"])
      first, second = alternatives.first(2)
      {
        "comparison_option_a" => describe_alternative(first),
        "comparison_option_b" => describe_alternative(second),
        "comparison_tradeoff" => tradeoff(first, second),
        "comparison_switch_condition" => comparison["decision_rule"]
      }.compact
    else
      {
        "comparison_rejected_alternative" => comparison["rejected_alternative"],
        "comparison_hard_constraint" => comparison["hard_constraint"],
        "comparison_decision_rule" => comparison["decision_rule"]
      }.compact
    end
  end

  def describe_alternative(alternative)
    return unless alternative.is_a?(Hash)

    alternative = alternative.deep_stringify_keys
    [
      alternative["option"],
      alternative["benefit"],
      alternative["cost_or_risk"].presence && "Risk: #{alternative['cost_or_risk']}",
      alternative["valid_when"].presence && "Use when: #{alternative['valid_when']}"
    ].compact.join(" ")
  end

  def tradeoff(first, second)
    return unless first.is_a?(Hash) && second.is_a?(Hash)

    first = first.deep_stringify_keys
    second = second.deep_stringify_keys
    "Option A offers #{first['benefit']} Its cost or risk is #{first['cost_or_risk']} Option B offers #{second['benefit']} Its cost or risk is #{second['cost_or_risk']}"
  end
end

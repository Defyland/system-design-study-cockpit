class MisconceptionClassifier
  CHECKPOINT_RULES = [
    [ /retry|idempot|duplic|cobrar|pagamento/i, "retry_without_idempotency" ],
    [ /cache|ttl|stale|fresh|invalida/i, "cache_without_freshness" ],
    [ /rate limit|waf|auth|gateway|autoriz/i, "auth_vs_rate_limit_confusion" ],
    [ /rollback|revert|canary|release|rollout/i, "rollback_hesitation" ],
    [ /metric|metrica|p95|latencia|erro|dashboard|sinal/i, "missing_first_metric" ],
    [ /scale|escala|pod|tenant|capacidade|delete|remov/i, "scale_before_delete" ],
    [ /uber|stripe|github|shopify|netflix|cloudflare|big tech/i, "overgeneralized_big_tech_case" ]
  ].freeze

  def self.for_checkpoint_attempt(attempt)
    return if attempt.correct? && attempt.high?

    text = [
      attempt.checkpoint.prompt,
      attempt.checkpoint.bad_answer,
      attempt.checkpoint.correction,
      attempt.prediction_text,
      attempt.decision_sentence
    ].compact.join("\n")

    CHECKPOINT_RULES.each do |pattern, key|
      return key if text.match?(pattern)
    end

    "tool_first"
  end

  def self.for_simulation_attempt(attempt)
    SimulationAttemptAssessment.new(attempt).misconception_key
  end
end

class SimulationAttemptAssessment
  SIMULATION_KEYS = {
    "load-balancer" => "scale_before_delete",
    "cache" => "cache_without_freshness",
    "rate-limit-vs-load-shedding" => "auth_vs_rate_limit_confusion",
    "circuit-breaker" => "retry_without_idempotency",
    "canary-rollout" => "rollback_hesitation"
  }.freeze

  def initialize(attempt)
    @attempt = attempt
  end

  def recommended_decision
    attempt.output_snapshot.to_h.fetch("recommendedDecision", nil)
  end

  def diverged?
    recommended_decision.present? && recommended_decision != attempt.decision
  end

  def reminder_needed?
    attempt.risky? || attempt.low? || diverged?
  end

  def severity
    return 3 if diverged?
    return 2 if attempt.risky? || attempt.low?

    1
  end

  def misconception_key
    return if recommended_decision == attempt.decision && attempt.high?

    SIMULATION_KEYS.fetch(attempt.simulation_slug, "missing_first_metric")
  end

  private

  attr_reader :attempt
end

require "test_helper"

class SimulationAttemptAssessmentTest < ActiveSupport::TestCase
  test "treats decision divergence as high severity" do
    assessment = SimulationAttemptAssessment.new(
      SimulationAttempt.new(
        simulation_slug: "canary-rollout",
        decision: "safe",
        confidence: "high",
        output_snapshot: { "recommendedDecision" => "rollback" }
      )
    )

    assert assessment.diverged?
    assert assessment.reminder_needed?
    assert_equal 3, assessment.severity
    assert_equal "rollback_hesitation", assessment.misconception_key
  end

  test "does not flag matching high confidence decisions" do
    assessment = SimulationAttemptAssessment.new(
      SimulationAttempt.new(
        simulation_slug: "canary-rollout",
        decision: "rollback",
        confidence: "high",
        output_snapshot: { "recommendedDecision" => "rollback" }
      )
    )

    refute assessment.diverged?
    refute assessment.reminder_needed?
    assert_equal 1, assessment.severity
    assert_nil assessment.misconception_key
  end

  test "flags low confidence even when decision matches" do
    assessment = SimulationAttemptAssessment.new(
      SimulationAttempt.new(
        simulation_slug: "canary-rollout",
        decision: "rollback",
        confidence: "low",
        output_snapshot: { "recommendedDecision" => "rollback" }
      )
    )

    refute assessment.diverged?
    assert assessment.reminder_needed?
    assert_equal 2, assessment.severity
    assert_equal "rollback_hesitation", assessment.misconception_key
  end

  test "uses first metric fallback for unknown simulation keys" do
    assessment = SimulationAttemptAssessment.new(
      SimulationAttempt.new(
        simulation_slug: "unknown-lab",
        decision: "safe",
        confidence: "high",
        output_snapshot: { "recommendedDecision" => "rollback" }
      )
    )

    assert_equal "missing_first_metric", assessment.misconception_key
  end
end

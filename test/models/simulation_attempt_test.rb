require "test_helper"

class SimulationAttemptTest < ActiveSupport::TestCase
  test "stores a simulator decision with snapshots" do
    attempt = SimulationAttempt.create!(
      simulation_slug: "load-balancer",
      decision: "risky",
      confidence: "medium",
      input_snapshot: { "requests" => 4_500 },
      output_snapshot: { "utilization" => 92.0 },
      feedback: "Conter tenant quente antes de escalar tudo."
    )

    assert_predicate attempt, :risky?
    assert_equal 4_500, attempt.input_snapshot.fetch("requests")
    assert_equal 92.0, attempt.output_snapshot.fetch("utilization")
  end
end

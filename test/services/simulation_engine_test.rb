require "test_helper"

class SimulationEngineTest < ActiveSupport::TestCase
  test "calculates load balancer output server side" do
    result = SimulationEngine.call(
      simulation_slug: "load-balancer",
      input_snapshot: {
        "requests" => 4_500,
        "servers" => 4,
        "serverCapacity" => 900,
        "failureRate" => 2
      }
    )

    assert_equal 4_500.0, result.input_snapshot.fetch("requests")
    assert_equal 125.0, result.output_snapshot.fetch("utilization")
    assert_equal 900.0, result.output_snapshot.fetch("rejected")
    assert_equal "rollback", result.output_snapshot.fetch("recommendedDecision")
  end

  test "normalizes missing and tampered inputs from the catalog bounds" do
    result = SimulationEngine.call(
      simulation_slug: "cache",
      input_snapshot: {
        "requests" => 999_999,
        "hitRate" => "not-a-number",
        "originCapacity" => 2_000
      }
    )

    assert_equal 40_000.0, result.input_snapshot.fetch("requests")
    assert_equal 72.0, result.input_snapshot.fetch("hitRate")
    assert_equal 120.0, result.input_snapshot.fetch("ttl")
  end
end

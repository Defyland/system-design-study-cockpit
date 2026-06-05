require "test_helper"

class RecordSimulationAttemptTest < ActiveSupport::TestCase
  test "derives output snapshot instead of trusting client-provided output" do
    attempt = RecordSimulationAttempt.call(
      attributes: {
        simulation_slug: "canary-rollout",
        decision: "safe",
        confidence: "high",
        input_snapshot: {
          "users" => 120_000,
          "rollout" => 5,
          "errorRate" => 6,
          "latencyP95" => 420
        },
        output_snapshot: {
          "recommendedDecision" => "safe",
          "feedback" => "Cliente tentou adulterar."
        }
      }
    )

    assert_equal "rollback", attempt.output_snapshot.fetch("recommendedDecision")
    assert_equal "rollback_hesitation", attempt.misconception_key
    assert_equal 1, MisconceptionEvent.where(source_kind: "simulation_attempt", source_id: attempt.id).count
  end

  test "keeps simulation attempt side effects atomic" do
    assert_no_difference -> { SimulationAttempt.count } do
      assert_no_difference -> { MisconceptionEvent.count } do
        assert_no_difference -> { Reminder.count } do
          assert_raises(ActiveRecord::RecordNotFound) do
            RecordSimulationAttempt.call(
              attributes: {
                simulation_slug: "missing-simulator",
                decision: "risky",
                confidence: "medium",
                input_snapshot: {}
              }
            )
          end
        end
      end
    end
  end
end

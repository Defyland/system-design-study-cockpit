require "test_helper"

class RecordSimulationAttemptTest < ActiveSupport::TestCase
  setup do
    StudyDocument.destroy_all
  end

  test "resolves simulation document from slug instead of trusting client document id" do
    wrong_document = StudyDocument.create!(
      kind: "simulation_lab",
      slug: "cache",
      title: "Cache Lab",
      source_path: "simulation-labs/cache.md",
      body_markdown: "# Cache",
      body_checksum: "cache"
    )
    correct_document = StudyDocument.create!(
      kind: "simulation_lab",
      slug: "canary-rollout",
      title: "Canary Rollout Lab",
      source_path: "simulation-labs/canary-rollout.md",
      body_markdown: "# Canary",
      body_checksum: "canary"
    )

    attempt = RecordSimulationAttempt.call(
      attributes: {
        study_document_id: wrong_document.id,
        simulation_slug: "canary-rollout",
        decision: "rollback",
        confidence: "high",
        input_snapshot: {
          "users" => 120_000,
          "rollout" => 5,
          "errorRate" => 6,
          "latencyP95" => 420
        }
      }
    )

    assert_equal correct_document, attempt.study_document
  end

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

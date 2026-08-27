require "test_helper"

class EnglishArcadeMockEvidenceTest < ActiveSupport::TestCase
  setup do
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
  end

  test "every registered mock has the authored phase sum and an initial/follow-up sequence" do
    EnglishArcadeCurriculum::MOCK_SPECS.each do |spec|
      expected = case spec.fetch("target")
      when "dsa" then [ 5, 8, 20, 8, 4 ]
      when "system_design" then [ 5, 5, 8, 10, 10, 5, 2 ]
      when "career" then [ 5, 12, 8, 5 ]
      else [ 8, 20, 10, 7 ]
      end
      assert_equal expected, spec.fetch("phases").map { |phase| phase.fetch("minutes") }, spec.fetch("id")
      assert_equal spec.fetch("required_card_keys").length * 2, spec.fetch("required_sequence").length
      spec.fetch("required_card_keys").each_with_index do |card_key, index|
        pair = spec.fetch("required_sequence").slice(index * 2, 2)
        assert_equal [ "initial", "follow_up" ], pair.map { |step| step.fetch("attempt_kind") }
        assert_equal [ card_key, card_key ], pair.map { |step| step.fetch("card_key") }
      end
    end
  end

  test "a mock without its correct challenge sequence fails closed" do
    session, initial, = build_dsa_mock
    assert_not EnglishArcadeMockEvidence.qualifying?(session: session, now: session.finished_at)
    assert_equal "sequence_length", EnglishArcadeMockEvidence.for(session: session, now: session.finished_at).fetch("reason")
    initial.update!(attempt_kind: "follow_up", variant_key: "follow_up")
    assert_not EnglishArcadeMockEvidence.qualifying?(session: session, now: session.finished_at)
  end

  test "a complete mock requires a real parent and critical artifacts" do
    session, initial, card = build_dsa_mock
    follow_up = session.english_arcade_attempts.create!(attempt_attributes(session, card, "follow_up", answered_at: session.started_at + 6.minutes, parent_attempt_id: initial.id))

    assert EnglishArcadeMockEvidence.qualifying?(session: session, now: session.finished_at)
    follow_up.update!(parent_attempt_id: nil)
    assert_not EnglishArcadeMockEvidence.qualifying?(session: session, now: session.finished_at)
  end

  test "a prompt snapshot mutation cannot qualify a mock after commit" do
    session, initial, card = build_dsa_mock
    follow_up = session.english_arcade_attempts.create!(attempt_attributes(session, card, "follow_up", answered_at: session.started_at + 6.minutes, parent_attempt_id: initial.id))
    assert EnglishArcadeMockEvidence.qualifying?(session: session, now: session.finished_at)

    tampered = follow_up.prompt_snapshot.merge("variant_digest" => "forged-digest")
    follow_up.update!(prompt_snapshot: tampered)
    refute EnglishArcadeMockEvidence.qualifying?(session: session, now: session.finished_at)
  end

  private

  def build_dsa_mock
    spec = EnglishArcadeCurriculum.mock("dsa_mock_01")
    started_at = 8.days.ago.change(usec: 0)
    finished_at = started_at + 45.minutes
    checkpoints = []
    cursor = started_at
    spec.fetch("phases").each_with_index do |phase, index|
      completed = cursor + phase.fetch("minutes").minutes
      artifact = "Phase #{index} records the contract, evidence boundary, failure mode, and verification signal."
      checkpoints << {
        "phase_id" => phase.fetch("id"), "phase_index" => index,
        "started_at" => cursor.iso8601(6), "completed_at" => completed.iso8601(6),
        "elapsed_seconds" => phase.fetch("minutes") * 60, "artifact" => artifact,
        "artifact_length" => artifact.length
      }
      cursor = completed
    end
    session = EnglishArcadeSession.create!(
      learner_key: "mock-contract",
      target: "dsa",
      mode: "timed_45",
      duration_seconds: 2_700,
      started_at: started_at,
      expires_at: finished_at,
      finished_at: finished_at,
      status: "completed",
      metadata: {
        "mock_id" => "dsa_mock_01", "curriculum_day" => 11, "exercise" => "initial",
        "required_card_keys" => spec.fetch("required_card_keys"), "scheduled_card_key" => nil,
        "content_version" => "1.4.0", "phase_state" => {
          "current_index" => spec.fetch("phases").length, "current_phase_started_at" => nil,
          "completed_at" => finished_at.iso8601(6), "checkpoints" => checkpoints
        }
      }
    )
    builder = EnglishArcadeSessionBuilder.new
    card = builder.card_for(target: "dsa", card_key: spec.fetch("required_card_keys").first, session: session, variant_id: "initial")
    initial = session.english_arcade_attempts.create!(attempt_attributes(session, card, "initial", answered_at: started_at + 1.minute))
    [ session, initial, card ]
  end

  def attempt_attributes(session, card, kind, answered_at:, parent_attempt_id: nil)
    variant_id = kind == "follow_up" ? "follow_up" : "initial"
    variant = EnglishArcadeAttemptContract.materialize(card.variants.fetch(variant_id), session_id: session.id.to_s, card_key: card.key).merge("content_version" => card.content_version)
    comparison = if card.critical_thinking.dig("comparison", "applicable") == true
      {
        "authored_applicable" => true, "comparison_option_a" => "Keep the simple window.",
        "comparison_option_b" => "Use indexed state.", "comparison_tradeoff" => "Memory buys fewer scans.",
        "comparison_switch_condition" => "Switch when the measured bound is exceeded."
      }
    else
      {
        "authored_applicable" => false, "comparison_rejected_alternative" => "The alternative violates the contract.",
        "comparison_hard_constraint" => "The input is a stream.", "comparison_decision_rule" => "Clarify before comparing."
      }
    end
    artifact = {
      "complete" => true, "captured_before_reveal" => true,
      "learner_classifications" => { "evidence_verified" => "The prompt states the input.", "evidence_inference" => "The state implies a window.", "evidence_assumption" => "The stream is bounded.", "evidence_gap" => "Scale needs measurement." },
      "problem_frame" => "The stream boundary must preserve the invariant under the stated workload.",
      "source_quality" => "The authored prompt is primary; runtime measurements remain a gap.",
      "comparison" => comparison,
      "counterexample" => "A duplicate at the boundary.", "confidence_percent" => 70, "change_my_mind" => "A trace would update me.",
      "fact_contract_accuracy" => { "source" => "authored_reference", "assessment_scope" => "not_assessed", "value" => nil },
      "semantic_quality" => { "source" => "not_assessed", "assessment_scope" => "not_assessed", "value" => nil }
    }
    {
      learner_key: session.learner_key, target: "dsa", card_key: card.key,
      attempt_kind: kind, variant_key: variant_id, answer_choice: variant.fetch("correct_choice"),
      typed_answer: "A typed answer states the invariant, evidence, trade-off, and next verification step.",
      correct: true, feedback_revealed: true, state: "scheduled", quality_score: 9,
      box_before: 1, box_after: 2, answered_at: answered_at, parent_attempt_id: parent_attempt_id,
      feynman_text: "The Feynman explanation names the invariant and the counterexample clearly.",
      diagnostic_evidence: {
        "answer_status" => "submitted", "outcome" => "submitted", "assessment_scope" => "server_contract",
        "production" => { "typed_length" => 90 }, "feynman_present" => true,
        "critical_artifact" => artifact,
        "assessment" => EnglishArcadeAttemptContract.frozen_contract(variant, content_version: card.content_version).merge(
          "variant_id" => variant_id, "variant_digest" => variant.fetch("digest"), "content_version" => card.content_version,
          "correct" => true, "selected_choice" => variant.fetch("correct_choice"), "critical_thinking" => card.critical_thinking,
          "contract_version" => EnglishArcadeAttemptContract::CONTRACT_VERSION
        )
      },
      prompt_snapshot: EnglishArcadeAttemptContract.snapshot(variant, content_version: card.content_version)
    }
  end
end

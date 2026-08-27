require "test_helper"

class EnglishArcadeProgressReportTest < ActiveSupport::TestCase
  setup do
    EnglishArcadeAttempt.delete_all
    EnglishArcadeSession.delete_all
    @session = EnglishArcadeSession.create!(learner_key: "metrics", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 10.days.ago, expires_at: 9.days.ago)
  end

  test "reports exact typed directness and delayed-retention denominators without inferring baseline" do
    parent = create_attempt(8.days.ago, "initial", true, 9, "english_direct")
    create_attempt(1.day.ago, "follow_up", true, 8, "mixed", parent)
    report = EnglishArcadeProgressReport.new(learner_key: "metrics").call

    assert_equal 2, report.dig(:direct_thinking, "eligible")
    assert_equal 1, report.dig(:direct_thinking, "direct")
    assert_equal 0.5, report.dig(:direct_thinking, "rate")
    assert_equal 1, report.dig(:delayed_retention, "eligible_events")
    assert_equal 1, report.dig(:delayed_retention, "successful_events")
    assert_equal 1.0, report.dig(:delayed_retention, "event_rate")
    assert_equal "pending", report.dig(:baseline, "status")
    assert_equal 1, report.dig(:follow_up_adaptation, "completed")
    assert_equal 0.5, report.dig(:follow_up_adaptation, "rate")
  end

  test "follow-up gate counts only a follow_up attempt, not other adaptations" do
    parent = create_attempt(1.day.ago, "initial", true, 9, "english_direct")
    %w[compression rephrase extension].each do |kind|
      create_attempt(Time.current, kind, true, 8, "english_direct", parent)
    end

    report = EnglishArcadeProgressReport.new(learner_key: "metrics").call
    assert_equal 1, report.dig(:follow_up_adaptation, "adaptation_completed")
    assert_equal 0, report.dig(:follow_up_adaptation, "follow_up_completed")

    create_attempt(Time.current, "follow_up", true, 8, "english_direct", parent)
    report = EnglishArcadeProgressReport.new(learner_key: "metrics").call
    assert_equal 1, report.dig(:follow_up_adaptation, "follow_up_completed")
  end

  test "delayed retention keeps event rate separate from distinct-card counts" do
    create_attempt(10.days.ago, "initial", true, 9, "english_direct")
    create_attempt(2.days.ago, "retry", false, 0, "english_direct")
    create_attempt(1.day.ago, "retry", false, 0, "english_direct")
    create_attempt(Time.current, "retry", true, 9, "english_direct")

    delayed = EnglishArcadeProgressReport.new(learner_key: "metrics").call.fetch(:delayed_retention)
    assert_equal 3, delayed.fetch("eligible_events")
    assert_equal 1, delayed.fetch("successful_events")
    assert_equal 0.333, delayed.fetch("event_rate")
    assert_equal 1, delayed.fetch("eligible_cards")
  end

  test "counts only a named mock after elapsed timed evidence and revealed production" do
    create_attempt(2.days.ago, "initial", true, 9, "english_direct")
    early = qualifying_mock_session("dsa_mock_01", started_at: 10.minutes.ago, finished_at: Time.current)
    initial = create_mock_attempt(early, "dsa-03-complexity-defence")
    create_mock_attempt(early, "dsa-03-complexity-defence", attempt_kind: "follow_up", parent_attempt: initial)

    report = EnglishArcadeProgressReport.new(learner_key: "metrics").call
    assert_empty report.dig(:mocks, "targets")

    early.update!(started_at: 46.minutes.ago, finished_at: Time.current)
    early.update!(metadata: early.metadata.merge("phase_state" => completed_phase_state(EnglishArcadeCurriculum.mock("dsa_mock_01"), early.started_at)))
    report = EnglishArcadeProgressReport.new(learner_key: "metrics").call
    assert_equal [ "dsa" ], report.dig(:mocks, "targets")
    assert_equal [ "dsa_mock_01" ], report.dig(:mocks, "completed_ids")
    assert_operator report.dig(:mocks, "sessions").first.fetch("elapsed_seconds"), :>=, 2430
    assert_equal 2430, report.dig(:mocks, "sessions").first.fetch("required_seconds")
  end

  test "counts due reviews only after a persisted due date, not immediate adaptation" do
    parent = create_attempt(8.days.ago, "initial", true, 9, "english_direct")
    parent.update!(next_due_on: 2.days.ago.to_date)
    create_attempt(7.days.ago, "follow_up", true, 8, "english_direct", parent)

    assert_equal 0, EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:srs_reviews, "due_completed")

    create_attempt(1.day.ago, "retry", true, 8, "english_direct", parent)
    report = EnglishArcadeProgressReport.new(learner_key: "metrics").call
    assert_equal 1, report.dig(:srs_reviews, "due_completed")
  end

  test "baseline axes use only the first revealed attempt for each exact baseline card" do
    create_attempt(3.days.ago, "initial", true, 9, "english_direct", nil, card_key: "dsa-01-pattern-naming", clarity: 1)
    create_attempt(1.day.ago, "retry", true, 9, "english_direct", nil, card_key: "dsa-01-pattern-naming", clarity: 4)
    create_attempt(1.day.ago, "initial", true, 9, "english_direct", nil, card_key: "dsa-02-invariant-statement", clarity: 4)

    baseline = EnglishArcadeProgressReport.new(learner_key: "metrics").call.fetch(:baseline)
    assert_equal 1, baseline.dig("language_axes", "clarity", "count")
    assert_equal 1.0, baseline.dig("language_axes", "clarity", "average")
  end

  test "baseline requires every exact card to have its curriculum target pairing" do
    baseline_ids = EnglishArcadeCurriculum::BASELINE_ITEM_IDS
    expected_targets = baseline_ids.to_h { |card_key| [ card_key, EnglishArcadeCurriculum.target_for(card_key) ] }

    baseline_ids.each_with_index do |card_key, index|
      target = expected_targets.fetch(card_key)
      target = expected_targets.fetch(baseline_ids.fetch(1)) if index.zero?
      target = expected_targets.fetch(baseline_ids.fetch(0)) if index == 1
      create_attempt(Time.current, "initial", true, 9, "english_direct", nil, target: target, card_key: card_key)
    end

    baseline = EnglishArcadeProgressReport.new(learner_key: "metrics").call.fetch(:baseline)
    assert_equal "pending", baseline.fetch("status")
    refute baseline.fetch("exact_target_pairing")
    refute baseline.dig("target_pairing", "exact")
    gap = baseline.fetch("pairing_gaps").find { |entry| entry.fetch("card_key") == baseline_ids.first }
    assert_equal expected_targets.fetch(baseline_ids.first), gap.fetch("expected_target")
    assert_equal expected_targets.fetch(baseline_ids.second), gap.fetch("actual_target")
  end

  test "high volume on an early day does not unlock future gates" do
    30.times { create_attempt(Time.current, "initial", true, 9, "english_direct") }

    report = EnglishArcadeProgressReport.new(learner_key: "metrics").call
    assert_equal 1, report.fetch(:program_day)
    assert_equal "pending", report.fetch(:gates).find { |gate| gate.fetch("day") == 30 }.fetch("status")
  end

  test "reached gate with insufficient evidence fails while future gate remains pending" do
    create_attempt(7.days.ago, "initial", true, 9, "english_direct")

    gates = EnglishArcadeProgressReport.new(learner_key: "metrics").call.fetch(:gates)
    assert_equal "fail", gates.find { |gate| gate.fetch("day") == 7 }.fetch("status")
    assert_equal "pending", gates.find { |gate| gate.fetch("day") == 14 }.fetch("status")
  end

  test "gate critical pairs use unique current assignment ids and ignore future or outsider ids" do
    report = EnglishArcadeProgressReport.new(learner_key: "metrics")
    day = EnglishArcadeCurriculum.plan.find { |entry| entry.fetch("day") == 7 }
    thresholds = day.dig("gate", "thresholds")
    current_ids = thresholds.fetch("required_item_ids")
    future_ids = EnglishArcadeCurriculum.required_item_ids_through(30) - current_ids
    metrics = gate_metric_fixture(thresholds)
    metrics["critical_pair_item_ids"] = future_ids.first(6)
    metrics["critical_pair_target_by_item"] = future_ids.first(6).to_h { |item_id| [ item_id, "dsa" ] }

    assert_equal 0, report.send(:gate_metric_value, "critical_pairs", 6, thresholds, metrics)
    assert_equal 0, report.send(:gate_metric_value, "critical_targets", 6, thresholds, metrics)

    metrics["critical_pair_item_ids"] = [ current_ids.first, current_ids.first, "outsider-card" ]
    metrics["critical_pair_target_by_item"] = { current_ids.first => EnglishArcadeCurriculum.target_for(current_ids.first), "outsider-card" => "dsa" }
    assert_equal 1, report.send(:gate_metric_value, "critical_pairs", 6, thresholds, metrics)
    refute report.send(:meets?, "critical_pairs", report.send(:gate_metric_value, "critical_pairs", 6, thresholds, metrics), 6)
  end

  test "delayed gate requires the exact cumulative scheduled item and variant set" do
    report = EnglishArcadeProgressReport.new(learner_key: "metrics")
    day = EnglishArcadeCurriculum.plan.find { |entry| entry.fetch("day") == 14 }
    thresholds = day.dig("gate", "thresholds")
    expected = thresholds.fetch("required_delayed_item_variant_ids")
    metrics = gate_metric_fixture(thresholds)
    metrics["delayed_retest_item_variant_ids"] = expected.first(6) + [ "future-card:delayed_variant" ]

    actual = report.send(:gate_metric_value, "required_delayed_item_variant_ids", expected, thresholds, metrics)
    assert_equal expected.first(6), actual
    refute report.send(:meets?, "required_delayed_item_variant_ids", actual, expected)

    metrics["delayed_retest_item_variant_ids"] = expected
    actual = report.send(:gate_metric_value, "required_delayed_item_variant_ids", expected, thresholds, metrics)
    assert_equal expected.sort, actual.sort
    assert report.send(:meets?, "required_delayed_item_variant_ids", actual, expected)
  end

  test "day thirty requires two critical pairs for every canonical target" do
    report = EnglishArcadeProgressReport.new(learner_key: "metrics")
    day = EnglishArcadeCurriculum.plan.find { |entry| entry.fetch("day") == 30 }
    thresholds = day.dig("gate", "thresholds")
    required_ids = thresholds.fetch("required_item_ids")
    metrics = gate_metric_fixture(thresholds)
    concentrated_ids = required_ids.first(26)
    metrics["critical_pair_item_ids"] = concentrated_ids
    metrics["critical_pair_target_by_item"] = concentrated_ids.to_h { |item_id| [ item_id, "dsa" ] }

    counts = report.send(:gate_metric_value, "critical_target_pair_counts", thresholds.fetch("critical_target_pair_counts"), thresholds, metrics)
    refute report.send(:meets?, "critical_target_pair_counts", counts, thresholds.fetch("critical_target_pair_counts"))

    valid_ids = required_ids.first(26)
    valid_targets = EnglishArcadeCurriculum::CANONICAL_TARGETS.flat_map { |target| [ target, target ] }
    metrics["critical_pair_item_ids"] = valid_ids
    metrics["critical_pair_target_by_item"] = valid_ids.zip(valid_targets).to_h
    counts = report.send(:gate_metric_value, "critical_target_pair_counts", thresholds.fetch("critical_target_pair_counts"), thresholds, metrics)
    assert report.send(:meets?, "critical_target_pair_counts", counts, thresholds.fetch("critical_target_pair_counts"))
  end

  test "ordinary timed sessions without mock_id never count" do
    ordinary = timed_session("dsa", "initial", [ "dsa-03-complexity-defence" ])
    create_mock_attempt(ordinary, "dsa-03-complexity-defence")

    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")
  end

  test "mock evidence rejects out-of-order, duplicate, outsider, and incomplete attempts" do
    spec = EnglishArcadeCurriculum.mock("dsa_mock_01")
    mock = qualifying_mock_session("dsa_mock_01")
    first = spec.fetch("required_card_keys").first
    create_mock_attempt(mock, first)
    mock.english_arcade_attempts.create!(learner_key: "metrics", target: "dsa", card_key: first, attempt_kind: "initial", typed_answer: meaningful_typed_answer, correct: true, feedback_revealed: true, state: "scheduled", quality_score: 9, box_before: 1, box_after: 2, answered_at: 1.second.from_now, feynman_text: meaningful_feynman_answer, diagnostic_evidence: production_evidence)
    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")

    outsider = qualifying_mock_session("dsa_mock_01")
    create_mock_attempt(outsider, "dsa-02-invariant-statement")
    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")
  end

  test "mock evidence rejects a wrong attempt until Black Box is complete" do
    mock = qualifying_mock_session("dsa_mock_01")
    attempt = create_mock_attempt(mock, "dsa-03-complexity-defence", correct: false, state: "feedback", quality: 0)
    assert_equal false, attempt.black_box_complete?
    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")
  end

  test "mock evidence requires the explicit Feynman flag in addition to text" do
    mock = qualifying_mock_session("dsa_mock_01")
    attempt = create_mock_attempt(mock, "dsa-03-complexity-defence")
    attempt.update!(diagnostic_evidence: production_evidence.except("feynman_present"))

    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")
  end

  test "expired mock evidence never satisfies a gate even with complete cards and phases" do
    mock = qualifying_mock_session("dsa_mock_01")
    create_mock_attempt(mock, "dsa-03-complexity-defence")
    mock.update!(status: "expired")

    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")
  end

  test "phase ledger timestamps outside the session window cannot satisfy mock evidence" do
    mock = qualifying_mock_session("dsa_mock_01")
    create_mock_attempt(mock, "dsa-03-complexity-defence")
    state = mock.metadata.fetch("phase_state").deep_dup
    state.fetch("checkpoints").first["started_at"] = (mock.started_at - 1.second).iso8601(6)
    mock.update!(metadata: mock.metadata.merge("phase_state" => state))

    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")
  end

  test "phase ledger rejects an artifact length that does not match the stored artifact" do
    mock = qualifying_mock_session("dsa_mock_01")
    create_mock_attempt(mock, "dsa-03-complexity-defence")
    state = mock.metadata.fetch("phase_state").deep_dup
    state.fetch("checkpoints").first["artifact_length"] += 1
    mock.update!(metadata: mock.metadata.merge("phase_state" => state))

    assert_empty EnglishArcadeProgressReport.new(learner_key: "metrics").call.dig(:mocks, "completed_ids")
  end

  private

  def gate_metric_fixture(thresholds)
    {
      "covered_item_ids" => thresholds.fetch("required_item_ids"),
      "critical_pair_item_ids" => [],
      "critical_pair_target_by_item" => {},
      "delayed_retest_item_variant_ids" => [],
      "delayed_retest_successful_item_variant_ids" => [],
      "canonical_item_accuracy" => {},
      "practice_dates_by_item" => {},
      "due_review_item_ids" => []
    }
  end

  def create_attempt(at, kind, correct, quality, directness, parent = nil, session: @session, target: "dsa", card_key: "dsa-01-pattern-naming", clarity: 3)
    EnglishArcadeAttempt.create!(
      english_arcade_session: session, learner_key: "metrics", target: target, card_key: card_key,
      attempt_kind: kind, parent_attempt: parent, answer_choice: "a", typed_answer: "A meaningful typed answer with an explicit decision, caveat, evidence, and next step for this report.",
      correct: correct, feedback_revealed: true, state: "scheduled", quality_score: quality, box_before: 1, box_after: 2,
      answered_at: at, diagnostic_evidence: { "production" => { "typed_length" => 90, "english_directness" => directness, "self_rubric" => { "clarity" => clarity, "precision" => 3, "naturalness" => 3, "pragmatic_appropriateness" => 3, "technical_correctness" => 3 } } }
    )
  end

  def production_evidence
    { "production" => { "typed_length" => 90, "english_directness" => "english_direct", "self_rubric" => { "clarity" => 3, "precision" => 3, "naturalness" => 3, "pragmatic_appropriateness" => 3, "technical_correctness" => 3 } }, "answer_status" => "correct", "outcome" => "correct", "feynman_present" => true }
  end

  def create_mock_attempt(session, card_key, correct: true, state: "scheduled", quality: 9, attempt_kind: "initial", parent_attempt: nil)
    variant_key = attempt_kind.to_s == "follow_up" ? "follow_up" : "initial"
    variant = {
      "id" => variant_key,
      "prompt" => "How would you defend this decision under a changed constraint?",
      "context" => "The interviewer asks for evidence, an alternative, and a failure mode.",
      "best_answer" => "I would state the invariant, compare alternatives, and verify the failure signal.",
      "distractors" => [ { "text" => "I would use a universal rule.", "why_wrong" => "It hides the workload and evidence boundary." } ],
      "feedback" => { "register" => "Lead with the decision." },
      "check" => { "feynman" => "Explain the invariant." },
      "critical_thinking" => { "comparison" => { "applicable" => false } }
    }
    materialized = EnglishArcadeAttemptContract.materialize(variant, session_id: session.id.to_s, card_key: card_key)
    content_version = "1.4.0"
    session.english_arcade_attempts.create!(
      learner_key: "metrics", target: EnglishArcadeCurriculum.target_for(card_key), card_key: card_key,
      attempt_kind: attempt_kind, parent_attempt: parent_attempt, variant_key: variant_key,
      answer_choice: materialized.fetch("correct_choice"), typed_answer: meaningful_typed_answer, correct: correct,
      feedback_revealed: true, state: state, quality_score: quality, box_before: 1, box_after: 2,
      answered_at: Time.current, feynman_text: meaningful_feynman_answer,
      prompt_snapshot: EnglishArcadeAttemptContract.snapshot(materialized, content_version: content_version),
      diagnostic_evidence: production_evidence.merge(
        "assessment_scope" => "server_contract",
        "selected_choice" => materialized.fetch("correct_choice"),
        "assessment" => EnglishArcadeAttemptContract.frozen_contract(materialized, content_version: content_version).merge(
          "contract_version" => EnglishArcadeAttemptContract::CONTRACT_VERSION,
          "variant_id" => variant_key,
          "variant_digest" => materialized.fetch("digest"),
          "content_version" => content_version,
          "correct" => correct,
          "selected_choice" => materialized.fetch("correct_choice"),
          "critical_thinking" => variant.fetch("critical_thinking")
        ),
        "critical_artifact" => mock_critical_artifact
      )
    )
  end

  def mock_critical_artifact
    {
      "complete" => true,
      "captured_before_reveal" => true,
      "learner_classifications" => {
        "evidence_verified" => "The prompt establishes the invariant.",
        "evidence_inference" => "The signal follows from the boundary.",
        "evidence_assumption" => "The workload remains within the stated limit.",
        "evidence_gap" => "Production scale still needs measurement."
      },
      "problem_frame" => "The interviewer needs a defensible decision under the stated workload.",
      "source_quality" => "The authored prompt is primary; runtime evidence remains pending.",
      "comparison" => {
        "authored_applicable" => false,
        "comparison_rejected_alternative" => "The alternative violates the same contract.",
        "comparison_hard_constraint" => "The input contract is fixed.",
        "comparison_decision_rule" => "Clarify the contract before comparing."
      },
      "counterexample" => "An adversarial input breaks the assumed bound.",
      "confidence_percent" => 70,
      "change_my_mind" => "A measured trace would update the recommendation.",
      "fact_contract_accuracy" => { "source" => "authored_reference", "assessment_scope" => "not_assessed", "value" => nil },
      "semantic_quality" => { "source" => "not_assessed", "assessment_scope" => "not_assessed", "value" => nil }
    }
  end

  def qualifying_mock_session(mock_id, started_at: 46.minutes.ago, finished_at: 1.minute.from_now)
    spec = EnglishArcadeCurriculum.mock(mock_id)
    EnglishArcadeSession.create!(
      learner_key: "metrics", target: spec.fetch("target"), mode: spec.fetch("mode"), duration_seconds: spec.fetch("duration_minutes") * 60,
      status: "completed", started_at: started_at, finished_at: finished_at, expires_at: finished_at,
      metadata: { "mock_id" => mock_id, "curriculum_day" => spec.fetch("day"), "exercise" => "initial", "required_card_keys" => spec.fetch("required_card_keys"), "scheduled_card_key" => nil, "content_version" => "1.4.0", "phase_state" => completed_phase_state(spec, started_at) }
    )
  end

  def completed_phase_state(spec, started_at)
    cursor = started_at
    checkpoints = spec.fetch("phases").map.with_index do |phase, index|
      completed_at = cursor + phase.fetch("minutes").to_i.minutes
      artifact = "A server-recorded #{phase.fetch('id')} artifact with the contract, evidence, edge case, and verification signal."
      checkpoint = {
        "phase_id" => phase.fetch("id"), "phase_index" => index,
        "started_at" => cursor.iso8601(6), "completed_at" => completed_at.iso8601(6),
        "elapsed_seconds" => (completed_at - cursor).round(3), "artifact" => artifact,
        "artifact_length" => artifact.length
      }
      cursor = completed_at
      checkpoint
    end
    { "current_index" => checkpoints.length, "current_phase_started_at" => nil, "completed_at" => cursor.iso8601(6), "checkpoints" => checkpoints }
  end

  def timed_session(target, exercise, required_card_keys = [])
    EnglishArcadeSession.create!(learner_key: "metrics", target: target, mode: target == "general" ? "timed_30" : "timed_45", duration_seconds: target == "general" ? 1800 : 2700,
      status: "completed", started_at: 46.minutes.ago, finished_at: Time.current, expires_at: Time.current,
      metadata: { "exercise" => exercise, "required_card_keys" => required_card_keys })
  end

  def meaningful_typed_answer
    "I would state the decision, name the trade-off, verify the boundary, and explain the evidence I would inspect before changing the implementation."
  end

  def meaningful_feynman_answer
    "I chose this option because it names the invariant, explains the trade-off, and gives me a concrete signal to verify before making the next decision."
  end
end

require "test_helper"

class EnglishArcadeCardTest < ActiveSupport::TestCase
  setup do
    EnglishArcadeCard.delete_all
    EnglishArcadeAttempt.delete_all
    EnglishArcadeSession.delete_all
    @card = EnglishArcadeCard.create!(
      learner_key: "study",
      target: "dsa",
      card_key: "dsa-1",
      due_on: Date.new(2026, 8, 23)
    )
    @at = Time.zone.local(2026, 8, 23, 9, 0, 0)
  end

  test "wrong answers return to box 1 with a daily interval" do
    @card.update!(box: 4, interval_days: 7)

    @card.record!(correct: false, at: @at)

    assert_equal 1, @card.box
    assert_equal 1, @card.interval_days
    assert_equal Date.new(2026, 8, 24), @card.due_on
  end

  test "correct answers advance through exact Leitner intervals" do
    expected = {
      2 => [ 2, Date.new(2026, 8, 25) ],
      3 => [ 4, Date.new(2026, 8, 27) ],
      4 => [ 7, Date.new(2026, 8, 30) ],
      5 => [ 14, Date.new(2026, 9, 6) ]
    }

    (2..5).each do |box|
      @card.update!(box: box - 1, interval_days: EnglishArcadeCard::BOX_INTERVALS.fetch(box - 1), due_on: @at.to_date)
      @card.record!(correct: true, at: @at)

      interval, due_on = expected.fetch(box)
      assert_equal box, @card.box
      assert_equal interval, @card.interval_days
      assert_equal due_on, @card.due_on
    end
  end

  test "mastery needs two high-quality variants separated by about a week" do
    session = EnglishArcadeSession.create!(
      learner_key: "study",
      target: "dsa",
      mode: "daily",
      duration_seconds: 600,
      started_at: @at,
      expires_at: @at + 600
    )
    first = EnglishArcadeAttempt.create!(attempt_attributes(session, "initial", @at, 9))
    # A report-only rephrase between the two critical variants must not make
    # the pair adjacent or become the qualifying variant itself.
    create_attempt(session, "rephrase", @at + 1.day, 8)
    second = create_attempt(session, "delayed_variant", @at + 7.days, 8)

    assert_equal "initial", first.variant_key
    assert_equal "delayed_variant", second.variant_key
    assert @card.mastered?
    assert_equal true, @card.mastery_progress.fetch("mastered")
    assert_equal [ [ "dsa", "dsa-1" ] ], EnglishArcadeCard.mastered_keys_for("study")
  end

  test "report-only rephrases never satisfy mastery by themselves" do
    session = EnglishArcadeSession.create!(
      learner_key: "study",
      target: "dsa",
      mode: "daily",
      duration_seconds: 600,
      started_at: @at,
      expires_at: @at + 600
    )
    EnglishArcadeAttempt.create!(attempt_attributes(session, "initial", @at, 9))
    create_attempt(session, "rephrase", @at + 7.days, 9)

    refute @card.mastered?
  end

  private

  def attempt_attributes(session, variant, answered_at, quality_score)
    authored_variant = {
      "id" => variant,
      "prompt" => "How would you defend this decision under a changed constraint?",
      "context" => "The interviewer asks for evidence, an alternative, and a failure mode.",
      "best_answer" => "I would state the invariant, compare alternatives, and verify the failure signal.",
      "distractors" => [ { "text" => "I would use a universal rule.", "why_wrong" => "It hides the workload and evidence boundary." } ],
      "feedback" => { "register" => "Lead with the decision." },
      "check" => { "feynman" => "Explain the invariant." },
      "critical_thinking" => { "comparison" => { "applicable" => false } }
    }
    materialized = EnglishArcadeAttemptContract.materialize(authored_variant, session_id: session.id.to_s, card_key: "dsa-1")
    content_version = "1.4.0"
    {
      english_arcade_session: session,
      learner_key: "study",
      target: "dsa",
      card_key: "dsa-1",
      attempt_kind: { "initial" => "initial", "follow_up" => "follow_up", "delayed_variant" => "retry" }.fetch(variant, "rephrase"),
      variant_key: variant,
      answer_choice: materialized.fetch("correct_choice"),
      correct: true,
      feedback_revealed: true,
      state: "revealed",
      quality_score: quality_score,
      answered_at: answered_at,
      typed_answer: "I would state the invariant, name the trade-off, verify the boundary, and explain the evidence.",
      prompt_snapshot: EnglishArcadeAttemptContract.snapshot(materialized, content_version: content_version),
      diagnostic_evidence: {
        "assessment_scope" => "server_contract",
        "selected_choice" => materialized.fetch("correct_choice"),
        "assessment" => {
          "contract_version" => EnglishArcadeAttemptContract::CONTRACT_VERSION,
          "content_version" => content_version,
          "variant_id" => variant,
          "variant_digest" => materialized.fetch("digest"),
          "correct_choice" => materialized.fetch("correct_choice"),
          "correct" => true,
          "critical_thinking" => authored_variant.fetch("critical_thinking")
        },
        "critical_artifact" => critical_artifact
      }
    }
  end

  def create_attempt(session, variant, answered_at, quality_score)
    EnglishArcadeAttempt.create!(attempt_attributes(session, variant, answered_at, quality_score))
  end

  def critical_artifact
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
end

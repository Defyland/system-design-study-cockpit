require "test_helper"

class EnglishArcadeAttemptContractTest < ActiveSupport::TestCase
  setup do
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
    @builder = EnglishArcadeSessionBuilder.new
    @session = EnglishArcadeSession.create!(
      learner_key: "contract-test",
      target: "dsa",
      mode: "daily",
      duration_seconds: 600,
      started_at: Time.current,
      expires_at: 10.minutes.from_now,
      metadata: { "exercise" => "initial", "content_version" => "1.4.0" }
    )
  end

  test "materializes opaque tokens bound to session, card, and variant" do
    first = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: @session, variant_id: "initial")
    other_session = @session.dup
    other_session.id = @session.id.to_i + 100_000
    other_session.save!(validate: false)
    other = @builder.card_for(target: "dsa", card_key: first.key, session: other_session, variant_id: "initial")

    refute_equal first.correct_choice, other.correct_choice
    assert_raises(EnglishArcadeAttemptContract::InvalidChoice) do
      @builder.grade(card: other, answer_choice: first.correct_choice)
    end
    assert first.options.all? { |choice| choice.id.match?(/\A[0-9a-f]{48}\z/) }
  ensure
    other_session&.destroy
  end

  test "server snapshot contains the bound contract while its public projection omits digest" do
    card = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: @session, variant_id: "follow_up")
    snapshot = @builder.prompt_snapshot(card)

    refute snapshot.key?("answer_text")
    refute snapshot.key?("correct_choice")
    refute snapshot.key?("feedback")
    refute snapshot.key?("check")
    refute snapshot.key?("critical_thinking")
    refute snapshot.key?("source")
    refute snapshot.key?("provenance")
    assert_equal "follow_up", snapshot.fetch("variant_id")
    assert_equal card.variant_digest, snapshot.fetch("variant_digest")

    public_snapshot = EnglishArcadeAttemptContract.public_snapshot(card.variant_contract, content_version: card.content_version)
    refute public_snapshot.key?("variant_digest")
    refute_includes public_snapshot.to_json, card.variant_digest
  end

  test "authored comparison branch rejects equal options and records false equivalence" do
    applicable = @builder.cards_for("dsa").map { |raw| @builder.card_for(target: "dsa", card_key: raw.fetch(:key), session: @session) }
      .find { |card| card.critical_thinking.dig("comparison", "applicable") == true }
    equal_payload = artifact_payload(applicable.critical_thinking).merge(
      "comparison_option_a" => "the same option",
      "comparison_option_b" => "the same option"
    )
    equal = EnglishArcadeAttemptContract.artifact_from(equal_payload, critical_thinking: applicable.critical_thinking)
    refute equal.fetch("complete")
    assert_includes equal.fetch("missing"), "comparison_option_a_and_b"

    rejected = @builder.cards_for("dsa").map { |raw| @builder.card_for(target: "dsa", card_key: raw.fetch(:key), session: @session) }
      .find { |card| card.critical_thinking.dig("comparison", "applicable") == false }
    false_branch = EnglishArcadeAttemptContract.artifact_from(artifact_payload(rejected.critical_thinking), critical_thinking: rejected.critical_thinking)
    assert false_branch.fetch("complete")
    assert_equal false, false_branch.dig("comparison", "authored_applicable")
  end

  test "variant contracts retain distinct authored digests" do
    initial = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: @session, variant_id: "initial")
    follow_up = @builder.card_for(target: "dsa", card_key: initial.key, session: @session, variant_id: "follow_up")
    delayed = @builder.card_for(target: "dsa", card_key: initial.key, session: @session, variant_id: "delayed_variant")

    assert_equal %w[initial follow_up delayed_variant], [ initial.variant_id, follow_up.variant_id, delayed.variant_id ]
    assert_equal 3, [ initial.variant_digest, follow_up.variant_digest, delayed.variant_digest ].uniq.length
  end

  test "follow-up owns its authored prompt, answer options, check, and token boundary" do
    initial = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: @session, variant_id: "initial")
    follow_up = @builder.card_for(target: "dsa", card_key: initial.key, session: @session, variant_id: "follow_up")

    refute_equal initial.prompt, follow_up.prompt
    refute_equal initial.answer_text, follow_up.answer_text
    assert_equal follow_up.variant_contract.fetch("check"), follow_up.feynman
    assert follow_up.variant_contract.dig("check", "challenge_kind").present?
    assert_includes follow_up.options.map(&:text), follow_up.answer_text
    refute_includes @builder.prompt_snapshot(follow_up).to_json, initial.prompt
    assert_raises(EnglishArcadeAttemptContract::InvalidChoice) do
      @builder.grade(card: follow_up, answer_choice: initial.correct_choice)
    end
  end

  test "follow-up and delayed Feynman checks never inherit the initial structure" do
    cards = EnglishArcade::Schema::CANONICAL_TARGETS.flat_map do |target|
      @builder.cards_for(target).map do |raw|
        @builder.card_for(target: target, card_key: raw.fetch(:key), session: @session, variant_id: "initial")
      end
    end
    assert_equal 164, cards.length

    forbidden_initial_keys = %w[concept explain_to constraint self_check reasoning_check]
    cards.each do |initial|
      initial_check = initial.variant_contract.fetch("check")
      %w[follow_up delayed_variant].each do |variant_id|
        variant = @builder.card_for(target: initial.target, card_key: initial.key, session: @session, variant_id: variant_id)
        check = variant.variant_contract.fetch("check")

        refute_equal initial_check, check, "#{initial.key}/#{variant_id} reused the initial Feynman structure"
        assert_empty check.keys & forbidden_initial_keys, "#{initial.key}/#{variant_id} leaked initial Feynman keys"
        assert_empty initial_check.to_a & check.to_a, "#{initial.key}/#{variant_id} shares initial Feynman entries"
      end
    end
  end

  test "learner-facing Feynman and feedback projections are explicit allowlists" do
    cards = EnglishArcade::Schema::CANONICAL_TARGETS.flat_map do |target|
      @builder.cards_for(target).map do |raw|
        @builder.card_for(target: target, card_key: raw.fetch(:key), session: @session, variant_id: "initial")
      end
    end
    assert_equal 164, cards.length

    forbidden_keys = %w[
      answer_anchors reasoning_moves variant_digest digest provenance variant_check
      critical_thinking answer best_answer correct_choice options
    ]
    cards.each do |initial|
      %w[initial follow_up delayed_variant].each do |variant_id|
        variant = @builder.card_for(target: initial.target, card_key: initial.key, session: @session, variant_id: variant_id)
        next unless variant

        dto = EnglishArcadeAttemptContract.public_feynman_dto(variant.variant_contract)
        assert_empty dto.keys & forbidden_keys, "#{initial.key}/#{variant_id} exposed an internal Feynman key"
        forbidden_keys.each { |key| refute dto.key?(key), "#{initial.key}/#{variant_id} exposed #{key}" }
        assert_equal variant_id, dto.fetch("variant_id")
        case variant_id
        when "initial"
          assert_equal variant.feynman.fetch("concept"), dto.fetch("concept")
          assert_equal variant.feynman.fetch("self_check"), dto.fetch("self_check")
        when "follow_up"
          assert_equal variant.feynman.fetch("goal"), dto.fetch("instruction")
          refute dto.key?("challenge_kind")
        when "delayed_variant"
          assert_equal variant.feynman.fetch("changed_constraint"), dto.fetch("changed_constraint")
          assert_equal variant.feynman.fetch("new_evidence"), dto.fetch("new_evidence")
        end
      end
    end

    follow_up = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: @session, variant_id: "follow_up")
    public_feedback = EnglishArcadeAttemptContract.public_feedback(follow_up.variant_contract)
    refute public_feedback.key?("variant_check")
    refute_includes public_feedback.to_json, "answer_anchors"
    refute_includes public_feedback.to_json, "reasoning_moves"
    refute_includes public_feedback.to_json, "variant_digest"
    assert_equal "follow_up", public_feedback.fetch("feynman").fetch("variant_id")
  end

  test "1.6 response versions stay content-side across public snapshot, Feynman, and feedback" do
    item = response_versions_sentinel_item
    versions = item.fetch("response_versions")
    variants = EnglishArcadeAttemptContract.variants_for(item)
    materialized = EnglishArcadeAttemptContract.materialize(
      variants.fetch("initial"),
      session_id: @session.id.to_s,
      card_key: item.fetch("id")
    )
    public_snapshot = EnglishArcadeAttemptContract.public_snapshot(materialized, content_version: "1.6.0")
    public_feynman = EnglishArcadeAttemptContract.public_feynman_dto(materialized)
    grade = EnglishArcadeAttemptContract.grade(materialized, answer_choice: materialized.fetch("correct_choice"))
    public_feedback = EnglishArcadeAttemptContract.public_feedback(materialized, feedback: grade.fetch("feedback"))

    [ variants, materialized, public_snapshot, public_feynman, public_feedback ].each do |surface|
      serialized = surface.to_json
      refute_includes serialized, "response_versions"
      refute_includes serialized, versions.fetch("short")
      refute_includes serialized, versions.fetch("deep")
    end

    # `medium` is required to equal `best_answer`; the current option contract
    # intentionally places that answer text in the correct choice. Remove the
    # option list to test the public metadata boundary without treating that
    # deliberate learner-visible choice as a response_versions leak.
    metadata_snapshot = public_snapshot.merge("options" => [])
    [ metadata_snapshot, public_feynman, public_feedback ].each do |surface|
      refute_includes surface.to_json, versions.fetch("medium")
    end
    assert_equal 1, public_snapshot.fetch("options").count { |option| option.fetch("text") == versions.fetch("medium") }
  end

  test "only initial, follow-up, and delayed variants are critical-eligible" do
    assert_equal %w[initial follow_up delayed_variant], EnglishArcadeEvidenceEligibility::CRITICAL_VARIANTS
    refute_includes EnglishArcadeEvidenceEligibility::CRITICAL_VARIANTS, "rephrase"
    refute_includes EnglishArcadeEvidenceEligibility::CRITICAL_VARIANTS, "compression"
    refute_includes EnglishArcadeEvidenceEligibility::CRITICAL_VARIANTS, "extension"
  end

  private

  def artifact_payload(critical)
    base = {
      "problem_frame" => "The user and workload define the boundary that must remain reliable.",
      "evidence_verified" => "The prompt establishes this boundary.",
      "evidence_inference" => "The likely implication follows from that trace.",
      "evidence_assumption" => "I assume the workload remains within this limit.",
      "evidence_gap" => "The scale and failure tolerance remain unknown.",
      "source_quality" => "The authored prompt is the primary source; production measurement is still missing.",
      "counterexample" => "A repeated or adversarial input could break it.",
      "confidence_percent" => 65,
      "change_my_mind" => "A measured trace would change my recommendation."
    }
    if critical.dig("comparison", "applicable") == true
      base.merge(
        "comparison_option_a" => "Keep the simpler implementation.",
        "comparison_option_b" => "Use the more scalable implementation.",
        "comparison_tradeoff" => "The second costs complexity for headroom.",
        "comparison_switch_condition" => "Switch when measured load crosses the bound."
      )
    else
      base.merge(
        "comparison_rejected_alternative" => "A tool-first comparison is rejected.",
        "comparison_hard_constraint" => "The options do not satisfy one contract.",
        "comparison_decision_rule" => "Clarify the contract before comparing."
      )
    end
  end

  def response_versions_sentinel_item
    short = "RV_SHORT_SENTINEL " + Array.new(19) { |index| "short_token_#{index}" }.join(" ")
    medium = "RV_MEDIUM_SENTINEL " + Array.new(49) { |index| "medium_token_#{index}" }.join(" ")
    deep = "RV_DEEP_SENTINEL " + Array.new(99) { |index| "deep_token_#{index}" }.join(" ")

    {
      "id" => "dsa-response-versions-sentinel",
      "version" => "1.6.0",
      "prompt" => "How would you defend this decision and identify the evidence that could change it?",
      "context" => "This synthetic item exists only to prove that authored response depth stays out of learner-facing runtime projections.",
      "best_answer" => medium,
      "response_versions" => { "short" => short, "medium" => medium, "deep" => deep },
      "distractors" => [
        { "text" => "I would choose a familiar pattern without naming its constraint or checking the evidence first.", "trap" => "precision", "why_wrong" => "It hides the decision boundary and makes an unsupported claim of confidence." },
        { "text" => "I would list every implementation detail before explaining the requirement or the failure mode.", "trap" => "pragmatics", "why_wrong" => "It delays the answer and does not show which evidence would change the recommendation." }
      ],
      "feedback" => {
        "register" => "Keep the answer direct and professional.",
        "hedging" => "Calibrate certainty to the evidence available.",
        "precision" => "Name the boundary and the verification step.",
        "grammar" => "Use a clear sequence of supported claims.",
        "pragmatics" => "Answer the interviewer before adding the caveat."
      },
      "feynman" => {
        "concept" => "Explain the decision boundary to a peer.",
        "explain_to" => "Describe the trade-off without adding unsupported facts.",
        "constraint" => "Keep the evidence boundary explicit.",
        "self_check" => "What observation would change the recommendation?"
      },
      "black_box" => {
        "repair" => "State the missing evidence and retry the decision."
      }
    }
  end
end

require "test_helper"

class EnglishArcadeCriticalContractTest < ActionDispatch::IntegrationTest
  setup do
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
    @builder = EnglishArcadeSessionBuilder.new
  end

  test "commits and reveals a session-bound contract without exposing future variants" do
    post "/english-arcade/sessions", params: { english_arcade_session: { target: "dsa", mode: "daily", card_key: "dsa-01-pattern-naming" } }
    session = EnglishArcadeSession.order(:id).last
    card = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: session, variant_id: "initial")

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        card_key: card.key, answer_choice: card.correct_choice, typed_answer: typed_answer,
        **artifact_for(card), confidence_percent: 72
      }
    }, as: :json
    assert_response :created
    attempt = session.english_arcade_attempts.order(:id).last
    snapshot = attempt.prompt_snapshot
    refute snapshot.key?("answer_text")
    refute snapshot.key?("correct_choice")
    refute snapshot.key?("feedback")
    refute snapshot.key?("check")
    refute snapshot.key?("critical_thinking")
    assert_equal card.variant_digest, attempt.diagnostic_evidence.dig("assessment", "variant_digest")
    assert attempt.diagnostic_evidence.dig("critical_artifact", "captured_before_reveal")

    get "/english-arcade.json", params: { session_id: session.id, attempt_id: attempt.id }
    assert_response :success
    refute_includes response.body, "variant_digest"
    refute_includes response.body, card.variant_digest

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: feynman_text }
    }, as: :json
    assert_response :success
    refute_includes response.body, "variant_digest"
    refute_includes response.body, card.variant_digest
    assert_equal true, JSON.parse(response.body).fetch("correct")
    assert_predicate attempt.reload, :feedback_revealed?
    assert_equal "committed_frozen_contract", attempt.diagnostic_evidence.fetch("reveal_source")
  end

  test "rejects an assessable initial without a complete critical artifact before persistence" do
    session = start_session
    card = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: session, variant_id: "initial")

    assert_incomplete_variant_rejected(session, card, exercise: "initial")
  end

  test "rejects an incomplete follow-up artifact without mutating progress or SRS" do
    initial_session = start_session
    initial = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: initial_session, variant_id: "initial")
    commit_and_reveal_initial(initial_session, initial)

    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: initial.key, exercise: "follow_up" }
    }
    follow_up_session = EnglishArcadeSession.order(:id).last
    follow_up = @builder.card_for(target: "dsa", card_key: initial.key, session: follow_up_session, variant_id: "follow_up")

    assert_incomplete_variant_rejected(follow_up_session, follow_up)
  end

  test "rejects an incomplete delayed artifact without mutating progress or SRS" do
    initial_session = start_session
    initial = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: initial_session, variant_id: "initial")
    parent = commit_and_reveal_initial(initial_session, initial)
    parent.update!(answered_at: 8.days.ago)

    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: initial.key, exercise: "retry" }
    }
    delayed_session = EnglishArcadeSession.order(:id).last
    delayed = @builder.card_for(target: "dsa", card_key: initial.key, session: delayed_session, variant_id: "delayed_variant")

    assert_incomplete_variant_rejected(delayed_session, delayed, exercise: "retry")
  end

  test "self-rubric is optional but supplied malformed or out-of-range values fail closed" do
    [ { self_clarity: "5" }, { self_precision: "not-a-number" } ].each do |invalid_rubric|
      session = start_session
      card = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: session, variant_id: "initial")
      wrong = card.options.find { |choice| choice.id != card.correct_choice }
      before_attempts = EnglishArcadeAttempt.count

      post "/english-arcade/attempts", params: {
        session_id: session.id,
        english_arcade_attempt: {
          card_key: card.key, answer_choice: wrong.id, typed_answer: typed_answer,
          **artifact_for(card), **invalid_rubric
        }
      }, as: :json

      assert_response :unprocessable_entity
      assert_equal "invalid_self_rubric", JSON.parse(response.body).fetch("error")
      assert_equal before_attempts, EnglishArcadeAttempt.count
    end
  end

  test "follow-up page uses its own prompt, check, options, and critical ledger" do
    session = start_session
    initial = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: session, variant_id: "initial")
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: initial.key, answer_choice: initial.correct_choice, typed_answer: typed_answer, **artifact_for(initial) }
    }, as: :json
    attempt = session.english_arcade_attempts.order(:id).last
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: feynman_text }
    }, as: :json
    assert_response :success
    assert_predicate attempt.reload, :critical_eligible?, attempt.diagnostic_evidence.inspect

    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: initial.key, exercise: "follow_up" }
    }
    follow_up_session = EnglishArcadeSession.order(:id).last
    follow_up = @builder.card_for(target: "dsa", card_key: initial.key, session: follow_up_session, variant_id: "follow_up")

    assert_precommit_variant_page(follow_up_session, follow_up, initial: initial)
    initial_critical = initial.critical_thinking
    inherited_critical_texts = [
      initial_critical.fetch("problem_frame"),
      *initial_critical.fetch("claim_map").values,
      initial_critical.dig("comparison", "decision_rule"),
      initial_critical.dig("failure_probe", "prompt"),
      initial_critical.dig("certainty", "rationale")
    ].compact
    inherited_critical_texts.each { |text| refute_includes response.body, text }
    follow_up_critical = follow_up.variant_contract.fetch("critical_thinking")
    %w[problem_frame claim_map failure_probe certainty].each { |key| refute follow_up_critical.key?(key) }
    assert_equal "follow_up", follow_up_critical.fetch("variant_id")
    assert_equal follow_up.variant_contract.fetch("check"), follow_up.feynman
    dto = EnglishArcadeAttemptContract.public_feynman_dto(follow_up.variant_contract)
    assert_equal follow_up.feynman.fetch("goal"), dto.fetch("instruction")
    refute dto.key?("challenge_kind")
  end

  test "post-commit follow-up and delayed Feynman steps use only their own checks" do
    initial_session = start_session
    initial = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: initial_session, variant_id: "initial")
    commit_and_reveal_initial(initial_session, initial)

    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: initial.key, exercise: "follow_up" }
    }
    follow_up_session = EnglishArcadeSession.order(:id).last
    follow_up = @builder.card_for(target: "dsa", card_key: initial.key, session: follow_up_session, variant_id: "follow_up")
    assert_precommit_variant_page(follow_up_session, follow_up, initial: initial)
    follow_up_attempt = commit_without_reveal(follow_up_session, follow_up, exercise: "follow_up")

    assert_post_commit_variant_page(
      follow_up_session, follow_up_attempt, follow_up,
      own_texts: [ follow_up.feynman.fetch("goal") ],
      initial: initial
    )

    delayed_initial_session = start_session
    delayed_initial = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: delayed_initial_session, variant_id: "initial")
    delayed_parent = commit_and_reveal_initial(delayed_initial_session, delayed_initial)
    delayed_parent.update!(answered_at: 8.days.ago)

    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: delayed_initial.key, exercise: "retry" }
    }
    delayed_session = EnglishArcadeSession.order(:id).last
    delayed = @builder.card_for(target: "dsa", card_key: delayed_initial.key, session: delayed_session, variant_id: "delayed_variant")
    assert_precommit_variant_page(delayed_session, delayed, initial: delayed_initial)
    delayed_attempt = commit_without_reveal(delayed_session, delayed, exercise: "retry")

    assert_post_commit_variant_page(
      delayed_session, delayed_attempt, delayed,
      own_texts: [ delayed.feynman.fetch("changed_constraint"), delayed.feynman.fetch("new_evidence") ],
      initial: delayed_initial
    )
  end

  test "rejects an opaque token from another session" do
    first = start_session
    second = start_session
    first_card = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: first, variant_id: "initial")
    second_card = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: second, variant_id: "initial")
    refute_equal first_card.correct_choice, second_card.correct_choice

    post "/english-arcade/attempts", params: {
      session_id: second.id,
      english_arcade_attempt: { card_key: second_card.key, answer_choice: first_card.correct_choice, typed_answer: typed_answer, **artifact_for(second_card) }
    }, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_answer_token", JSON.parse(response.body).fetch("error")
    assert_empty second.english_arcade_attempts
  end

  test "self-ratings cannot turn a wrong contract into mastery" do
    session = start_session
    card = @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming", session: session, variant_id: "initial")
    wrong = card.options.find { |choice| choice.id != card.correct_choice }
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        card_key: card.key, answer_choice: wrong.id, typed_answer: typed_answer,
        **artifact_for(card), english_directness: "english_direct", self_clarity: 4,
        self_precision: 4, self_naturalness: 4, self_pragmatic_appropriateness: 4,
        self_technical_correctness: 4
      }
    }, as: :json
    assert_response :created
    attempt = session.english_arcade_attempts.order(:id).last
    post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: feynman_text } }, as: :json
    assert_response :success
    assert_equal false, attempt.reload.correct
    assert_equal 0, attempt.quality_score
    refute attempt.critical_eligible? && EnglishArcadeAttemptContract.mastery_eligible?(attempt)
  end

  private

  def start_session
    post "/english-arcade/sessions", params: { english_arcade_session: { target: "dsa", mode: "daily", card_key: "dsa-01-pattern-naming" } }
    EnglishArcadeSession.order(:id).last
  end

  def typed_answer
    "I would state the invariant, compare the trade-off, name the failure mode, and verify the decision with a focused test."
  end

  def feynman_text
    "The invariant preserves the decision boundary; the counterexample shows which assumption must be tested before I generalise it."
  end

  def commit_and_reveal_initial(session, card)
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: card.correct_choice, typed_answer: typed_answer, **artifact_for(card) }
    }, as: :json
    assert_response :created
    attempt = session.english_arcade_attempts.order(:id).last

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: feynman_text }
    }, as: :json
    assert_response :success
    attempt.reload
  end

  def commit_without_reveal(session, card, exercise:)
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        card_key: card.key,
        exercise: exercise,
        answer_choice: card.correct_choice,
        typed_answer: typed_answer,
        **artifact_for(card)
      }
    }, as: :json
    assert_response :created
    payload = JSON.parse(response.body)
    assert_public_feynman_dto(card, payload.fetch("feynman"))
    refute payload.to_json.include?("variant_check")
    refute payload.to_json.include?("answer_anchors")
    refute payload.to_json.include?("reasoning_moves")
    refute payload.to_json.include?("variant_digest")
    refute payload.to_json.include?(card.variant_digest)
    session.english_arcade_attempts.order(:id).last
  end

  def assert_post_commit_variant_page(session, attempt, card, own_texts:, initial:)
    initial_check = initial.variant_contract.fetch("check")
    active_check = card.variant_contract.fetch("check")
    refute_equal initial_check, active_check
    assert_empty initial_check.to_a & active_check.to_a
    %w[concept explain_to constraint self_check reasoning_check].each do |key|
      refute active_check.key?(key)
    end

    get "/english-arcade", params: { session_id: session.id, attempt_id: attempt.id }
    assert_response :success
    own_texts.compact.each { |text| assert_includes response.body, text }
    initial_check.values.flatten.compact.each { |text| refute_includes response.body, text.to_s if text.is_a?(String) && text.length >= 8 }
    assert_no_public_internal_variant_fields(response.body, card: card, initial: initial)
    refute_includes response.body, "variant_digest"
    refute_includes response.body, card.variant_digest

    get "/english-arcade.json", params: { session_id: session.id, attempt_id: attempt.id }
    assert_response :success
    payload = JSON.parse(response.body)
    dto = payload.fetch("feynman")
    assert_equal card.variant_id, dto.fetch("variant_id")
    assert_public_feynman_dto(card, dto)
    refute payload.to_json.include?("variant_check")
    refute payload.to_json.include?("answer_anchors")
    refute payload.to_json.include?("reasoning_moves")
    refute_includes response.body, "variant_digest"
    refute_includes response.body, card.variant_digest

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: feynman_text }
    }, as: :json
    assert_response :success
    revealed_payload = JSON.parse(response.body)
    feedback = revealed_payload.fetch("feedback")
    assert_public_feynman_dto(card, feedback.fetch("feynman"))
    refute feedback.key?("variant_check")
    refute revealed_payload.to_json.include?("answer_anchors")
    refute revealed_payload.to_json.include?("reasoning_moves")
    refute revealed_payload.to_json.include?("variant_digest")
    refute revealed_payload.to_json.include?(card.variant_digest)

    get "/english-arcade", params: { session_id: session.id, attempt_id: attempt.id }
    assert_response :success
    assert_no_public_internal_variant_fields(response.body, card: card, initial: initial)
    get "/english-arcade.json", params: { session_id: session.id, attempt_id: attempt.id }
    assert_response :success
    refute_includes response.body, "variant_check"
    refute_includes response.body, "answer_anchors"
    refute_includes response.body, "reasoning_moves"
    refute_includes response.body, "variant_digest"
    refute_includes response.body, card.variant_digest
  end

  def assert_precommit_variant_page(session, card, initial:)
    get "/english-arcade", params: { session_id: session.id }
    assert_response :success
    assert_includes response.body, card.prompt
    assert_includes response.body, card.context
    card.options.each { |option| assert_includes response.body, option.text }
    assert_no_public_internal_variant_fields(response.body, card: card, initial: initial, allow_active_values: false)
    refute_includes response.body, "provenance"
    refute_includes response.body, "variant_digest"
    refute_includes response.body, card.variant_digest

    get "/english-arcade.json", params: { session_id: session.id }
    assert_response :success
    payload = JSON.parse(response.body)
    public_card = payload.fetch("cards").fetch(0)
    assert_equal card.prompt, public_card.fetch("prompt")
    assert_equal card.context, public_card.fetch("context")
    assert_equal card.options.map(&:text).sort, public_card.fetch("options").map { |choice| choice.fetch("text") }.sort
    refute payload.to_json.include?("feynman")
    refute payload.to_json.include?("variant_check")
    refute payload.to_json.include?("answer_anchors")
    refute payload.to_json.include?("reasoning_moves")
    refute payload.to_json.include?("variant_digest")
    refute payload.to_json.include?("provenance")
    refute payload.to_json.include?(card.variant_digest)
    active_check_values(card).each { |text| refute_includes payload.to_json, text if text.length >= 8 }
    future_variant_prompts(card).each { |text| refute_includes payload.to_json, text if text.length >= 8 }
  end

  def assert_no_public_internal_variant_fields(body, card:, initial:, allow_active_values: true)
    forbidden_keys = %w[active_check variant_check answer_anchors reasoning_moves variant_digest digest]
    forbidden_keys.each { |key| refute_includes body, key }
    unless allow_active_values
      active_check_values(card).each { |text| refute_includes body, text if text.length >= 8 }
    end
    initial_check_values(initial).each { |text| refute_includes body, text if text.length >= 8 }
    future_variant_prompts(card).each { |text| refute_includes body, text if text.length >= 8 }
  end

  def active_check_values(card)
    card.variant_contract.fetch("check", {}).values.flat_map { |value| value.is_a?(Array) ? value : [ value ] }.filter_map do |value|
      value.to_s if value.is_a?(String)
    end
  end

  def initial_check_values(card)
    card.variant_contract.fetch("check", {}).values.flat_map { |value| value.is_a?(Array) ? value : [ value ] }.filter_map do |value|
      value.to_s if value.is_a?(String)
    end
  end

  def future_variant_prompts(card)
    card.variants.to_h.values.filter_map do |variant|
      prompt = variant.is_a?(Hash) ? (variant["prompt"] || variant[:prompt]).to_s : nil
      prompt if prompt.present? && prompt != card.prompt
    end
  end

  def assert_public_feynman_dto(card, dto)
    forbidden_keys = %w[answer_anchors reasoning_moves variant_digest digest provenance variant_check critical_thinking]
    assert_empty dto.keys & forbidden_keys
    case card.variant_id.to_s
    when "follow_up"
      assert_equal card.feynman.fetch("goal"), dto.fetch("instruction")
      refute dto.key?("challenge_kind")
    when "delayed_variant"
      assert_equal card.feynman.fetch("changed_constraint"), dto.fetch("changed_constraint")
      assert_equal card.feynman.fetch("new_evidence"), dto.fetch("new_evidence")
    end
  end

  def assert_incomplete_variant_rejected(session, card, exercise: "follow_up")
    before_attempts = EnglishArcadeAttempt.count
    before_schedules = EnglishArcadeCard.order(:id).pluck(:id, :box, :interval_days, :due_on, :attempts_count, :correct_count, :last_correct)
    before_mastery = EnglishArcadeCard.mastered_keys_for("anonymous")
    before_question_count = session.question_count
    before_score = session.score
    before_metadata = session.metadata.deep_dup

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        card_key: card.key,
        exercise: exercise,
        answer_choice: card.correct_choice,
        typed_answer: typed_answer
      }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "critical_artifact_incomplete", JSON.parse(response.body).fetch("error")
    assert_equal before_attempts, EnglishArcadeAttempt.count
    assert_equal before_schedules, EnglishArcadeCard.order(:id).pluck(:id, :box, :interval_days, :due_on, :attempts_count, :correct_count, :last_correct)
    assert_equal before_mastery, EnglishArcadeCard.mastered_keys_for("anonymous")
    assert_equal before_question_count, session.reload.question_count
    assert_equal before_score, session.reload.score
    assert_equal before_metadata, session.reload.metadata
    assert_empty session.english_arcade_attempts
  end

  def artifact_for(card)
    base = {
      problem_frame: "The interviewer needs a bounded decision for the stated input and workload.",
      evidence_verified: "The prompt establishes the input contract.",
      evidence_inference: "The invariant follows from the contiguous window.",
      evidence_assumption: "I assume the stream remains within bounded memory.",
      evidence_gap: "The peak workload still needs measurement.",
      source_quality: "The authored prompt is primary; runtime evidence remains pending.",
      counterexample: "A duplicate at the boundary could break the window.",
      change_my_mind: "A trace showing a different bound would change my choice.",
      confidence_percent: 70
    }
    if card.critical_thinking.dig("comparison", "applicable") == true
      base.merge(comparison_option_a: "Keep a simple window.", comparison_option_b: "Use indexed last-seen state.", comparison_tradeoff: "The index costs memory for fewer scans.", comparison_switch_condition: "Switch when measured input size makes scans unsafe.")
    else
      base.merge(comparison_rejected_alternative: "A tool-first alternative is not comparable.", comparison_hard_constraint: "The question requires the same input contract.", comparison_decision_rule: "Clarify the contract before choosing.")
    end
  end
end

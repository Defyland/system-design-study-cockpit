require "test_helper"

class EnglishArcadeControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
    @builder = EnglishArcadeSessionBuilder.new
  end

  test "prompt JSON omits answer keys before a Feynman reveal" do
    get "/english-arcade.json"

    assert_response :success
    payload = JSON.parse(response.body)
    refute payload.to_json.include?("correct_choice")
    refute payload.to_json.include?("answer_text")
    assert_equal false, payload.fetch("feedback_revealed")
    assert_equal 30, payload.fetch("thirty_day_plan").length
    assert_equal 3, payload.fetch("thirty_day_plan").count { |day| day.fetch("mocks").any? { |mock| mock.fetch("target") == "dsa" } }
    assert_equal 3, payload.fetch("thirty_day_plan").count { |day| day.fetch("mocks").any? { |mock| mock.fetch("target") == "system_design" } }
    assert payload.fetch("thirty_day_plan").all? do |day|
      day.key?("interleaving") && day.key?("weak_area_remediation") && day.dig("assignment", "selector").present?
    end
    progress = payload.fetch("progress_30_days")
    assert_equal "not_assessed", progress.fetch("skill_evidence").fetch("listening").fetch("status")
    assert progress.fetch("feedback_evidence").key?("register")
    assert_equal 0, progress.fetch("capture_evidence").fetch("typed_count")
    assert_equal "pending", progress.fetch("baseline").fetch("status")
    assert_equal 0, progress.fetch("delayed_retention").fetch("eligible_events")
    assert_equal true, progress.fetch("self_rubric").fetch("clarity").fetch("self_assessed")

    session = start_session
    get "/english-arcade.json", params: { session_id: session.id }
    active_payload = JSON.parse(response.body)
    assert_predicate active_payload.fetch("cards"), :any?
    refute active_payload.to_json.include?("correct_choice")
    refute active_payload.to_json.include?("answer_text")
  end

  test "guided launcher persists its experience and exposes study material without an assessment form" do
    get "/english-arcade"
    assert_response :success
    assert_includes response.body, "Play falling cards"
    assert_includes response.body, "guided study arcade"

    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "career", mode: "daily", experience: "guided" }
    }
    assert_response :redirect
    session = EnglishArcadeSession.order(:id).last
    assert_equal "guided", session.metadata.fetch("experience")

    get "/english-arcade", params: { session_id: session.id }
    assert_response :success
    assert_includes response.body, "Best answer · practise in first person"
    assert_includes response.body, "Canonical response"
    assert_includes response.body, "Trade-off or trap"
    assert_includes response.body, "Critical-thinking path"
    assert_includes response.body, "Sources and evidence boundary"
    assert_includes response.body, "Falling phrase round"
    assert_includes response.body, "Review again"
    assert_equal 5, response.body.scan('class="guided-card"').length
    refute_includes response.body, "Commit answer"
    refute_includes response.body, "Feynman pass before the reveal"
    refute_match(%r{action="[^"]*english-arcade/attempts}, response.body)
    assert_empty EnglishArcadeAttempt.where(english_arcade_session: session)
    assert_empty EnglishArcadeCard.where(learner_key: "anonymous", target: "career")

    card = @builder.call(target: "career", learner_key: "anonymous", session: session, limit: 1).cards.first
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: card.correct_choice, typed_answer: meaningful_typed_answer }
    }, as: :json
    assert_response :unprocessable_entity
    assert_equal "guided_session_is_non_assessing", JSON.parse(response.body).fetch("error")
    assert_empty EnglishArcadeAttempt.where(english_arcade_session: session)
  end

  test "new sessions persist a private randomized deck seed" do
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "rails", mode: "daily", experience: "assessment" }
    }

    session = EnglishArcadeSession.order(:id).last
    assert_match(/\A[0-9a-f]{32}\z/, session.metadata.fetch("deck_seed"))
    assert_nil session.metadata.fetch("scheduled_card_key")
  end

  test "best answer fill is revealed only on an explicit valid assessment request" do
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "rails", mode: "daily", experience: "assessment" }
    }
    session = EnglishArcadeSession.order(:id).last
    card = @builder.call(target: "rails", learner_key: "anonymous", session: session, limit: 1, persist_schedules: false).cards.first

    get "/english-arcade", params: { session_id: session.id }
    assert_response :success
    assert_includes response.body, "data-best-answer-fill-url"
    refute_includes response.body, "data-best-answer-fill="

    post "/english-arcade/best-answer-fill", params: { session_id: session.id, card_key: card.key }, as: :json

    assert_response :success
    fill = JSON.parse(response.body)
    assert_equal card.correct_choice, fill.fetch("answer_choice")
    assert_equal card.answer_text, fill.fetch("typed_answer")
    refute fill.key?("self_technical_correctness")

    post "/english-arcade/best-answer-fill", params: { session_id: session.id, card_key: "rails-future-card" }, as: :json
    assert_response :not_found
  end

  test "guided sessions cannot request the assessment best answer fill" do
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "career", mode: "daily", experience: "guided" }
    }
    session = EnglishArcadeSession.order(:id).last

    post "/english-arcade/best-answer-fill", params: { session_id: session.id, card_key: "career-01-a-60-to-90-second-introduction" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "guided_session_is_non_assessing", JSON.parse(response.body).fetch("error")
  end

  test "interview mode renders resume-backed questions without local paths or contact details" do
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "interview", mode: "timed_45", experience: "guided" }
    }
    session = EnglishArcadeSession.order(:id).last

    get "/english-arcade", params: { session_id: session.id }

    assert_response :success
    assert_includes response.body, "connects your backend scale"
    assert_includes response.body, "100 million requests per day"
    assert_includes response.body, "eight microfrontends"
    assert_includes response.body, "Samsung Tizen"
    assert_includes response.body, "transactional outbox"
    assert_includes response.body, "four critical services"
    assert_includes response.body, "twenty-five minutes to eight minutes"
    assert_includes response.body, "seven seconds to two seconds"
    assert_includes response.body, "Yellow Team"
    assert_includes response.body, "2.5 million clients"
    assert_includes response.body, "allan_flavio_resume_fullstack_v3.pdf"
    refute_includes response.body, "/Users/"
    refute_match(/resume PDF is absent/i, response.body)
    refute_match(/self-reported|needs? confirmation|confirmation required/i, response.body)
    refute_match(/linkedin\.com|mailto:|\+\d{2}/i, response.body)
  end

  test "guided finish completes the session without diagnostic evidence" do
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "career", mode: "daily", experience: "guided" }
    }
    session = EnglishArcadeSession.order(:id).last

    post finish_english_arcade_path, params: { session_id: session.id }

    assert_response :redirect
    assert_equal "completed", session.reload.status
    assert_includes flash[:notice], "no diagnostic attempt was recorded"
    assert_empty EnglishArcadeAttempt.where(english_arcade_session: session)
  end

  test "pre-Feynman correct and incorrect choices remain neutral in history and JSON" do
    [ true, false ].each do |correct_choice|
      session = start_session
      card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1, session: session).cards.first
      choice = correct_choice ? card.correct_choice : card.options.find { |option| option.id != card.correct_choice }.id

      post "/english-arcade/attempts", params: {
        session_id: session.id,
        english_arcade_attempt: { card_key: card.key, answer_choice: choice, typed_answer: meaningful_typed_answer, **self_rubric_params }
      }, as: :json
      assert_response :created
      attempt = EnglishArcadeAttempt.order(:id).last
      refute attempt.feedback_revealed?

      get "/english-arcade.json", params: { session_id: session.id, attempt_id: attempt.id }
      assert_response :success
      refute response.body.include?("\"answer_text\"")
      refute card.sources.any? { |source| response.body.include?(source.to_json) }
      refute response.body.match?(%r{(?:/|@)[0-9a-f]{7,64}})

      get "/english-arcade", params: { session_id: session.id, attempt_id: attempt.id }
      assert_response :success
      assert_includes response.body, "Feedback locked"
      refute_match(/>Correct</, response.body)
      refute_match(/>Needs another pass</, response.body)
    end
  end

  test "experience provenance stays out of snapshots and Feynman HTML until reveal" do
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "go_experience", mode: "daily" }
    }
    session = EnglishArcadeSession.order(:id).last
    card = @builder.call(target: "go_experience", learner_key: "anonymous", limit: 1, session: session).cards.first
    source_path = card.sources.first.fetch("path")
    commit = card.provenance.fetch("files").first.fetch("commit")
    safe_version = card.provenance.fetch("safe_interview_version")
    visible_evidence = [ source_path, commit, safe_version, card.provenance.fetch("verified_claims").first ]

    get "/english-arcade.json", params: { session_id: session.id }
    assert_response :success
    refute visible_evidence.any? { |value| response.body.include?(value) }

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: card.correct_choice, typed_answer: meaningful_typed_answer, **self_rubric_params }
    }, as: :json
    assert_response :created
    attempt = EnglishArcadeAttempt.order(:id).last
    refute attempt.prompt_snapshot.keys.any? { |key| %w[source sources provenance].include?(key) }
    refute attempt.diagnostic_evidence.key?("feedback")
    refute attempt.diagnostic_evidence.to_json.match?(%r{(?:/|@)[0-9a-f]{7,64}})

    get "/english-arcade", params: { session_id: session.id, attempt_id: attempt.id }
    assert_response :success
    refute visible_evidence.any? { |value| response.body.include?(value) }

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: meaningful_feynman_answer }
    }, as: :json
    assert_response :success
    revealed = JSON.parse(response.body)
    assert_equal card.sources, revealed.fetch("feedback").fetch("sources")
    assert_equal card.provenance, revealed.fetch("feedback").fetch("provenance")
    assert visible_evidence.all? { |value| response.body.include?(value) }

    get "/english-arcade", params: { session_id: session.id, attempt_id: attempt.id }
    assert_response :success
    assert visible_evidence.all? { |value| response.body.include?(value) }
  end

  test "curriculum card launch derives the canonical target and preserves the requested card" do
    item_id = EnglishArcadeCurriculum::BASELINE_ITEM_IDS.last

    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "mixed", mode: "daily", card_key: item_id }
    }

    session = EnglishArcadeSession.order(:id).last
    assert_equal "system_design", session.target
    assert_equal item_id, session.metadata.fetch("scheduled_card_key")
    assert_redirected_to english_arcade_path(session_id: session.id)
  end

  test "scheduled reattempt persists an authoritative cross-session parent and ignores forged submission fields" do
    item_id = "dsa-02-invariant-statement"
    parent_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 8.days.ago, expires_at: 8.days.ago)
    parent = revealed_attempt(english_arcade_session: parent_session, card_key: item_id, answered_at: 7.days.ago)
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "mixed", mode: "daily", card_key: item_id, exercise: "retry" }
    }

    session = EnglishArcadeSession.order(:id).last
    assert_equal "dsa", session.target
    assert_equal "retry", session.metadata.fetch("exercise")
    assert_equal item_id, session.metadata.fetch("scheduled_card_key")
    assert_equal parent.id, session.metadata.fetch("parent_attempt_id")
    assert_redirected_to english_arcade_path(session_id: session.id)

    bound_retry_card = @builder.card_for(target: "dsa", card_key: item_id, session: session, variant_id: "delayed_variant")

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        card_key: "dsa-01-pattern-naming", attempt_kind: "initial", parent_attempt_id: 999_999,
        answer_choice: bound_retry_card.correct_choice, typed_answer: meaningful_typed_answer,
        **critical_artifact_params(bound_retry_card), **self_rubric_params
      }
    }
    attempt = EnglishArcadeAttempt.order(:id).last
    assert_equal item_id, attempt.card_key
    assert_equal "retry", attempt.attempt_kind
    assert_equal parent.id, attempt.parent_attempt_id

    get "/english-arcade", params: { session_id: session.id, card_key: "dsa-01-pattern-naming", exercise: "initial" }
    assert_response :success
    assert_includes response.body, bound_retry_card.prompt
    refute_includes response.body, @builder.card_for(target: "dsa", card_key: "dsa-01-pattern-naming").prompt
  end

  test "delayed retry chooses the newest eligible initial despite later ineligible lineage" do
    item_id = "dsa-02-invariant-statement"
    old_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 9.days.ago, expires_at: 9.days.ago)
    old_initial = revealed_attempt(english_arcade_session: old_session, card_key: item_id, answered_at: 8.days.ago)

    recent_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 2.days.ago, expires_at: 2.days.ago)
    recent_initial = revealed_attempt(english_arcade_session: recent_session, card_key: item_id, answered_at: 1.day.ago)
    broken_evidence = recent_initial.diagnostic_evidence.deep_dup
    broken_evidence.fetch("critical_artifact")["complete"] = false
    recent_initial.update!(diagnostic_evidence: broken_evidence)

    later_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 1.day.ago, expires_at: 1.day.ago)
    follow_up = revealed_attempt(english_arcade_session: later_session, card_key: item_id, answered_at: 2.hours.ago)
    follow_up.update!(attempt_kind: "follow_up", variant_key: "follow_up")
    compression = revealed_attempt(english_arcade_session: later_session, card_key: item_id, answered_at: 1.hour.ago)
    compression.update!(attempt_kind: "compression", variant_key: "compression")

    before = EnglishArcadeSession.count
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: item_id, exercise: "retry" }
    }

    assert_redirected_to english_arcade_path(session_id: EnglishArcadeSession.order(:id).last.id)
    assert_equal before + 1, EnglishArcadeSession.count
    assert_equal old_initial.id, EnglishArcadeSession.order(:id).last.metadata.fetch("parent_attempt_id")
  end

  test "delayed retry rejects a parent whose frozen digest no longer matches" do
    item_id = "dsa-02-invariant-statement"
    parent_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 9.days.ago, expires_at: 9.days.ago)
    parent = revealed_attempt(english_arcade_session: parent_session, card_key: item_id, answered_at: 8.days.ago)
    evidence = parent.diagnostic_evidence.deep_dup
    evidence.fetch("assessment")["variant_digest"] = "tampered-digest"
    parent.update!(diagnostic_evidence: evidence)

    before = EnglishArcadeSession.count
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: item_id, exercise: "retry" }
    }

    assert_response :redirect
    assert_equal before, EnglishArcadeSession.count
  end

  test "adaptive launch rejects missing, incompatible, and incomplete latest parents" do
    item_id = "dsa-02-invariant-statement"

    assert_adaptive_launch_rejected(item_id)
    other_card_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 8.days.ago)
    revealed_attempt(english_arcade_session: other_card_session, card_key: "dsa-01-pattern-naming", answered_at: 6.days.ago)
    assert_adaptive_launch_rejected(item_id)

    other_learner_session = EnglishArcadeSession.create!(learner_key: "another-learner", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 8.days.ago)
    revealed_attempt(english_arcade_session: other_learner_session, learner_key: "another-learner", card_key: item_id, answered_at: 5.days.ago)
    assert_adaptive_launch_rejected(item_id)

    other_target_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "rails", mode: "daily", duration_seconds: 600, started_at: 8.days.ago)
    revealed_attempt(english_arcade_session: other_target_session, target: "rails", card_key: item_id, answered_at: 4.days.ago)
    assert_adaptive_launch_rejected(item_id)

    old_valid_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 8.days.ago)
    revealed_attempt(english_arcade_session: old_valid_session, card_key: item_id, answered_at: 3.days.ago)
    wrong_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 8.days.ago)
    wrong_parent = revealed_attempt(english_arcade_session: wrong_session, card_key: item_id, correct: false, state: "feedback", answered_at: 2.days.ago)
    assert_adaptive_launch_rejected(item_id)

    complete_black_box!(wrong_parent)
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: item_id, exercise: "follow_up" }
    }
    adaptive = EnglishArcadeSession.order(:id).last
    assert_equal "follow_up", adaptive.metadata.fetch("exercise")
    assert_equal wrong_parent.id, adaptive.metadata.fetch("parent_attempt_id")
  end

  test "adaptive commit rejects incompatible server metadata" do
    card_key = "dsa-02-invariant-statement"
    other_parent_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "dsa", mode: "daily", duration_seconds: 600, started_at: 2.days.ago)
    wrong_card_parent = revealed_attempt(english_arcade_session: other_parent_session, card_key: "dsa-01-pattern-naming", answered_at: 1.day.ago)
    adaptive = EnglishArcadeSession.create!(
      learner_key: "anonymous",
      target: "dsa",
      mode: "daily",
      duration_seconds: 600,
      started_at: Time.current,
      expires_at: 10.minutes.from_now,
      metadata: { "exercise" => "retry", "scheduled_card_key" => card_key, "parent_attempt_id" => wrong_card_parent.id }
    )

    before = EnglishArcadeAttempt.count
    post "/english-arcade/attempts", params: {
      session_id: adaptive.id,
      english_arcade_attempt: { answer_choice: "a", typed_answer: meaningful_typed_answer, **self_rubric_params }
    }

    assert_response :redirect
    assert_equal before, EnglishArcadeAttempt.count
    assert_includes flash[:alert], "same card"
  end

  test "final general timed mock progresses through its three required cards and rejects outsiders" do
    post "/english-arcade/sessions", params: { english_arcade_session: { target: "general", mode: "timed_30", card_key: "general-06-star-conflict" } }
    arcade_session = EnglishArcadeSession.order(:id).last
    assert_equal EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS, arcade_session.metadata.fetch("required_card_keys")
    assert_nil arcade_session.metadata.fetch("scheduled_card_key")

    get "/english-arcade.json", params: { session_id: arcade_session.id }
    payload = JSON.parse(response.body)
    assert_equal [ EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS.first ], payload.fetch("cards").map { |card| card.fetch("key") }
    EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS.drop(1).each do |future_key|
      future_prompt = @builder.card_for(target: "general", card_key: future_key, session: arcade_session, variant_id: "initial").prompt
      refute_includes payload.to_json, future_prompt
    end
    refute payload.to_json.include?("answer_text")

    get "/english-arcade", params: { session_id: arcade_session.id, card_key: "general-04-respectful-disagreement" }
    assert_response :success
    assert_includes response.body, @builder.card_for(target: "general", card_key: "general-06-star-conflict").prompt
    refute_includes response.body, @builder.card_for(target: "general", card_key: "general-04-respectful-disagreement").prompt

    before = EnglishArcadeAttempt.count
    post "/english-arcade/attempts", params: {
      session_id: arcade_session.id,
      english_arcade_attempt: { card_key: "general-04-respectful-disagreement", answer_choice: "a", typed_answer: meaningful_typed_answer, **self_rubric_params }
    }
    assert_response :redirect
    assert_equal before, EnglishArcadeAttempt.count
    assert_includes flash[:alert], "next required card"

    EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS.each_with_index do |card_key, index|
      card = @builder.card_for(target: "general", card_key: card_key)
      commit_and_reveal(arcade_session, card)
      get "/english-arcade.json", params: { session_id: arcade_session.id }
      remaining = JSON.parse(response.body).fetch("cards").map { |entry| entry.fetch("key") }
      assert_equal EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS.drop(index + 1).first(1), remaining
    end
    assert_equal EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS, arcade_session.english_arcade_attempts.order(:id).pluck(:card_key)
  end

  test "Salesforce legacy fixture remains ineligible for adaptive practice without a critical contract" do
    card_key = "salesforce-01-bulkification"
    parent_session = EnglishArcadeSession.create!(learner_key: "anonymous", target: "salesforce", mode: "daily", duration_seconds: 600, started_at: 2.days.ago)
    parent = revealed_attempt(english_arcade_session: parent_session, target: "salesforce", card_key: card_key, answered_at: 1.day.ago)

    before = EnglishArcadeSession.count
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "salesforce", mode: "daily", card_key: card_key, exercise: "follow_up" }
    }

    assert_response :redirect
    assert_equal before, EnglishArcadeSession.count
    assert_includes flash[:alert], "latest revealed attempt"
    refute_predicate parent, :critical_eligible?
  end

  test "required mock locks the next card until Feynman and Black Box complete the current miss" do
    post "/english-arcade/sessions", params: { english_arcade_session: { target: "general", mode: "timed_30", card_key: "general-06-star-conflict" } }
    mock = EnglishArcadeSession.order(:id).last
    first = @builder.card_for(target: "general", card_key: "general-06-star-conflict", session: mock, variant_id: "initial")
    second_key = "general-09-incident-update"
    wrong_choice = first.options.find { |choice| choice.id != first.correct_choice }
    post "/english-arcade/attempts", params: { session_id: mock.id, english_arcade_attempt: { card_key: first.key, answer_choice: wrong_choice.id, typed_answer: meaningful_typed_answer, **self_rubric_params } }
    assert_required_mock_locked(mock, second_key)

    attempt = EnglishArcadeAttempt.order(:id).last
    post "/english-arcade/attempts", params: { session_id: mock.id, english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: meaningful_feynman_answer } }
    assert_required_mock_locked(mock, second_key)

    post finish_english_arcade_path, params: { session_id: mock.id }
    assert_response :redirect
    assert_equal "active", mock.reload.status
    assert_includes flash[:alert], "Complete every required card in order"

    post "/english-arcade/attempts", params: { session_id: mock.id, english_arcade_attempt: black_box_params(attempt.id) }
    get "/english-arcade.json", params: { session_id: mock.id }
    assert_equal second_key, JSON.parse(response.body).fetch("cards").first.fetch("key")
  end

  test "required mock finish requires the complete ordered and qualified trio" do
    mock = start_required_mock
    first_key, second_key, third_key = EnglishArcadeCurriculum::GENERAL_FINAL_MOCK_ITEM_IDS

    assert_required_mock_finish_blocked(mock)

    commit_and_reveal(mock, @builder.card_for(target: "general", card_key: first_key))
    assert_required_mock_finish_blocked(mock)

    wrong_attempt = commit_wrong_and_complete_black_box(mock, @builder.card_for(target: "general", card_key: second_key))
    assert_predicate wrong_attempt, :feedback_revealed?
    assert_predicate wrong_attempt, :black_box_complete?
    assert_equal "scheduled", wrong_attempt.state
    assert_required_mock_finish_blocked(mock)

    commit_and_reveal(mock, @builder.card_for(target: "general", card_key: third_key))
    post finish_english_arcade_path, params: { session_id: mock.id }

    assert_response :redirect
    assert_equal "completed", mock.reload.status
  end

  test "does not accept spoken text as an assessable production input" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1, session: session).cards.first

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: card.options.find { |option| option.id != card.correct_choice }.id, spoken_text: meaningful_typed_answer, **self_rubric_params }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "meaningful_typed_production_required", JSON.parse(response.body).fetch("error")
  end

  test "an error requires five actionable Black Box fields before scheduling" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1, session: session).cards.first

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        card_key: card.key,
        answer_choice: card.options.find { |option| option.id != card.correct_choice }.id,
        attempt_kind: "initial", typed_answer: meaningful_typed_answer, **self_rubric_params
      }
    }
    attempt = EnglishArcadeAttempt.order(:id).last
    assert_equal "feynman", attempt.state
    refute attempt.feedback_revealed?

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        attempt_id: attempt.id,
        card_key: card.key,
        phase: "feynman",
        feynman_text: meaningful_feynman_answer
      }
    }
    assert_redirected_to %r{/english_arcade\?}
    attempt.reload
    assert_equal "feedback", attempt.state
    assert_predicate attempt, :feedback_revealed?
    assert_equal 0, EnglishArcadeCard.find_by!(learner_key: "anonymous", target: "dsa", card_key: card.key).attempts_count

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        attempt_id: attempt.id,
        card_key: card.key,
        phase: "postmortem",
        postmortem_text: "I didn't know"
      }
    }
    assert_redirected_to %r{/english_arcade\?}
    assert_includes flash[:alert], "five Black Box fields"
    assert_equal "feedback", attempt.reload.state
    assert_equal 0, EnglishArcadeCard.find_by!(learner_key: "anonymous", target: "dsa", card_key: card.key).attempts_count

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        attempt_id: attempt.id,
        card_key: card.key,
        phase: "postmortem",
        black_box_root_cause: "I changed the pointer before stating the invariant.",
        black_box_missing_signal: "The boundary condition was not observable in my explanation.",
        black_box_preventive_rule: "State the invariant and counterexample before editing the loop.",
        black_box_targeted_exercise: "Solve one sliding-window variant while narrating the invariant.",
        black_box_retest_dates: "Retry tomorrow and again seven days from today."
      }
    }
    attempt.reload
    card_schedule = EnglishArcadeCard.find_by!(learner_key: "anonymous", target: "dsa", card_key: card.key)
    assert_equal "scheduled", attempt.state
    assert_equal 1, card_schedule.attempts_count
    assert_equal 1, card_schedule.box

    # A correct/scheduled attempt cannot be reset by forging a post-mortem phase.
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        attempt_id: attempt.id,
        card_key: card.key,
        phase: "postmortem",
        black_box_root_cause: "Forged update should not be accepted.",
        black_box_missing_signal: "Forged update should not be accepted.",
        black_box_preventive_rule: "Forged update should not be accepted.",
        black_box_targeted_exercise: "Forged update should not be accepted.",
        black_box_retest_dates: "Forged update should not be accepted."
      }
    }
    assert_redirected_to %r{/english_arcade\?}
    assert_equal "scheduled", attempt.reload.state
    assert_equal 1, card_schedule.reload.attempts_count
  end

  test "rejects an assessable choice without meaningful typed production" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1, session: session).cards.first

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: "b", attempt_kind: "initial", typed_answer: "too short" }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "meaningful_typed_production_required", JSON.parse(response.body).fetch("error")
    assert_equal 0, EnglishArcadeAttempt.count
  end

  test "skip is a persisted incorrect branch and cannot reveal without Feynman" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1, session: session).cards.first

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, attempt_kind: "initial", answer_status: "skip" }
    }
    attempt = EnglishArcadeAttempt.order(:id).last
    assert_equal "feynman", attempt.state
    assert_equal "skip", attempt.diagnostic_evidence.fetch("answer_status")
    refute attempt.feedback_revealed?

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, card_key: card.key, phase: "feynman", feynman_text: meaningful_feynman_answer }
    }
    attempt.reload
    assert_equal "feedback", attempt.state
    refute attempt.correct?
    assert_equal 0, EnglishArcadeCard.find_by!(learner_key: "anonymous", target: "dsa", card_key: card.key).attempts_count
  end

  test "JSON Black Box completion returns scheduling evidence without answer metadata" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1, session: session).cards.first

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: card.options.find { |option| option.id != card.correct_choice }.id, attempt_kind: "initial", typed_answer: meaningful_typed_answer, **self_rubric_params }
    }, as: :json
    attempt_id = JSON.parse(response.body).fetch("attempt_id")

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        attempt_id: attempt_id,
        card_key: card.key,
        phase: "feynman",
        feynman_text: meaningful_feynman_answer
      }
    }, as: :json
    assert_response :success
    assert_equal true, JSON.parse(response.body).fetch("black_box_required")

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        attempt_id: attempt_id,
        card_key: card.key,
        phase: "postmortem",
        black_box_root_cause: "I moved the pointer before stating the invariant.",
        black_box_missing_signal: "The boundary condition was absent from my explanation.",
        black_box_preventive_rule: "State the invariant before changing the loop.",
        black_box_targeted_exercise: "Solve one variant while narrating the invariant.",
        black_box_retest_dates: "Retest tomorrow and again seven days from today."
      }
    }, as: :json

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "scheduled", payload.fetch("state")
    assert_equal false, payload.fetch("black_box_required")
    assert_equal 1, payload.fetch("box_after")
    refute payload.to_json.include?("correct_choice")
    refute payload.to_json.include?("answer_text")
  end

  test "registered mocks are authoritative at launch, including interview target" do
    EnglishArcadeCurriculum::MOCK_SPECS.each do |spec|
      post "/english-arcade/sessions", params: {
        english_arcade_session: {
          mock_id: spec.fetch("id"), target: spec.fetch("target"), mode: spec.fetch("mode"),
          card_key: spec.fetch("required_card_keys").first, exercise: "initial"
        }
      }
      assert_response :redirect
      arcade_session = EnglishArcadeSession.order(:id).last
      assert_equal spec.fetch("id"), arcade_session.metadata.fetch("mock_id")
      assert_equal spec.fetch("day"), arcade_session.metadata.fetch("curriculum_day")
      assert_equal spec.fetch("target"), arcade_session.target
      assert_equal spec.fetch("mode"), arcade_session.mode
      assert_equal spec.fetch("required_card_keys"), arcade_session.metadata.fetch("required_card_keys")
      assert_nil arcade_session.metadata.fetch("scheduled_card_key")
    end
  end

  test "rejects unknown, mismatched, adaptive, and wrong-anchor mock launches" do
    before = EnglishArcadeSession.count
    post "/english-arcade/sessions", params: { english_arcade_session: { mock_id: "not-a-mock", target: "dsa", mode: "timed_45", card_key: "dsa-03-complexity-defence" } }
    assert_response :redirect
    assert_equal before, EnglishArcadeSession.count

    spec = EnglishArcadeCurriculum.mock("dsa_mock_01")
    [
      { target: "rails", mode: "timed_45", card_key: spec.fetch("required_card_keys").first },
      { target: "dsa", mode: "timed_30", card_key: spec.fetch("required_card_keys").first },
      { target: "dsa", mode: "timed_45", card_key: "dsa-01-pattern-naming" },
      { target: "dsa", mode: "timed_45", card_key: spec.fetch("required_card_keys").first, exercise: "follow_up" }
    ].each do |attrs|
      current = EnglishArcadeSession.count
      post "/english-arcade/sessions", params: { english_arcade_session: attrs.merge(mock_id: spec.fetch("id")) }
      assert_response :redirect
      assert_equal current, EnglishArcadeSession.count
    end
  end

  test "mock finish stays active before ninety percent and accepts a wrong answer after Black Box" do
    session = start_registered_mock("dsa_mock_01")
    card = @builder.card_for(target: "dsa", card_key: "dsa-03-complexity-defence")
    commit_and_reveal(session, card)

    post finish_english_arcade_path, params: { session_id: session.id }
    assert_response :redirect
    assert_equal "active", session.reload.status
    assert_includes flash[:alert], "90%"

    session = start_registered_mock("dsa_mock_01")
    commit_wrong_and_complete_black_box(session, card)
    follow_up_card = @builder.card_for(target: "dsa", card_key: card.key, session: session, variant_id: "follow_up")
    follow_up_attempt = commit_and_reveal(session, follow_up_card, exercise: "follow_up")
    assert_equal "follow_up", follow_up_attempt.attempt_kind
    assert_equal session.english_arcade_attempts.where(attempt_kind: "initial").order(:id).last.id, follow_up_attempt.parent_attempt_id
    finish_at = complete_mock_phases(session, "dsa_mock_01")
    travel_to(finish_at) { post finish_english_arcade_path, params: { session_id: session.id } }
    assert_response :redirect
    assert_equal "completed", session.reload.status
  end

  test "mock finish rejects revealed text when the Feynman presence flag is absent" do
    session = start_registered_mock("dsa_mock_01")
    card = @builder.card_for(target: "dsa", card_key: "dsa-03-complexity-defence")
    commit_and_reveal(session, card)
    attempt = session.english_arcade_attempts.order(:id).last
    attempt.update!(diagnostic_evidence: attempt.diagnostic_evidence.except("feynman_present"))
    finish_at = complete_mock_phases(session, "dsa_mock_01")

    travel_to(finish_at) { post finish_english_arcade_path, params: { session_id: session.id } }
    assert_response :redirect
    assert_equal "active", session.reload.status
  end

  test "mock finish rejects an outsider attempt even when the required card passed" do
    session = start_registered_mock("dsa_mock_01")
    card = @builder.card_for(target: "dsa", card_key: "dsa-03-complexity-defence")
    commit_and_reveal(session, card)
    EnglishArcadeAttempt.create!(
      english_arcade_session: session, learner_key: "anonymous", target: "dsa", card_key: "dsa-01-pattern-naming",
      attempt_kind: "initial", typed_answer: meaningful_typed_answer, correct: true, feedback_revealed: true,
      state: "scheduled", quality_score: 8, box_before: 1, box_after: 2, answered_at: 1.second.from_now,
      feynman_text: meaningful_feynman_answer, diagnostic_evidence: { "production" => { "typed_length" => 90 }, "answer_status" => "correct", "outcome" => "correct" }
    )
    finish_at = complete_mock_phases(session, "dsa_mock_01")

    travel_to(finish_at) { post finish_english_arcade_path, params: { session_id: session.id } }
    assert_response :redirect
    assert_equal "active", session.reload.status
  end

  test "phase transitions reject short, reordered, and duplicate artifacts without mutating the ledger" do
    session = start_registered_mock("dsa_mock_01")
    spec = EnglishArcadeCurriculum.mock("dsa_mock_01")
    first = spec.fetch("phases").first
    original = session.reload.metadata.fetch("phase_state").deep_dup
    long_artifact = "A typed phase artifact states the contract, edge cases, invariant, and verification signal for this coding scenario."

    post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { phase: "mock_phase", phase_id: "choose_approach", phase_artifact: long_artifact } }, as: :json
    assert_response :unprocessable_entity
    assert_equal original, session.reload.metadata.fetch("phase_state")

    post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { phase: "mock_phase", phase_id: first.fetch("id"), phase_artifact: "too short" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal original, session.reload.metadata.fetch("phase_state")

    travel_to(session.started_at + 271.seconds) do
      post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { phase: "mock_phase", phase_id: first.fetch("id"), phase_artifact: long_artifact, phase_index: 99, elapsed_seconds: 0 } }, as: :json
      assert_response :success
    end
    after_first = session.reload.metadata.fetch("phase_state").deep_dup
    assert_equal 1, after_first.fetch("current_index")

    travel_to(session.started_at + 272.seconds) do
      post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { phase: "mock_phase", phase_id: first.fetch("id"), phase_artifact: long_artifact } }, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal after_first, session.reload.metadata.fetch("phase_state")
  end

  test "system design mock runs every server-owned phase and reports a completed index" do
    session = start_registered_mock("system_design_mock_01")
    finish_at = complete_mock_phases(session, "system_design_mock_01")

    get "/english-arcade.json", params: { session_id: session.id }
    assert_response :success
    payload = JSON.parse(response.body).fetch("mock")
    assert_equal "complete", payload.fetch("status")
    assert_equal payload.fetch("phase_count"), payload.fetch("phase_index")
    assert_equal payload.fetch("phase_count"), payload.fetch("completed_phase_ids").length
    refute response.body.include?("#{payload.fetch('phase_count') + 1} of #{payload.fetch('phase_count')}")
    assert_operator finish_at, :<, session.reload.expires_at
  end

  test "phase completion respects the ninety-percent floor at the one-second boundary" do
    session = start_registered_mock("dsa_mock_01")
    phase = EnglishArcadeCurriculum.mock("dsa_mock_01").fetch("phases").first
    artifact = "A typed phase artifact states the contract, edge cases, invariant, and verification signal for this coding scenario."
    start = session.reload.started_at

    travel_to(start + 269.seconds, with_usec: true) do
      post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { phase: "mock_phase", phase_id: phase.fetch("id"), phase_artifact: artifact } }, as: :json
      assert_response :unprocessable_entity
    end
    assert_empty session.reload.metadata.fetch("phase_state").fetch("checkpoints")

    travel_to(start + 270.seconds, with_usec: true) do
      post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { phase: "mock_phase", phase_id: phase.fetch("id"), phase_artifact: artifact } }, as: :json
      assert_response :success
    end
    assert_equal 1, session.reload.metadata.fetch("phase_state").fetch("checkpoints").length
  end

  test "phase endpoint expires an ended session instead of accepting a late artifact" do
    session = start_registered_mock("dsa_mock_01")
    session.update!(expires_at: 1.second.ago)
    phase = EnglishArcadeCurriculum.mock("dsa_mock_01").fetch("phases").first

    post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { phase: "mock_phase", phase_id: phase.fetch("id"), phase_artifact: "A valid artifact that arrives after the session expiry and must be rejected." } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "expired", session.reload.status
    assert_empty session.reload.metadata.fetch("phase_state").fetch("checkpoints")
  end

  private

  def start_session
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily" }
    }
    assert_response :redirect
    EnglishArcadeSession.order(:id).last
  end

  def start_required_mock
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "general", mode: "timed_30", card_key: "general-06-star-conflict" }
    }
    assert_response :redirect
    EnglishArcadeSession.order(:id).last
  end

  def start_registered_mock(mock_id)
    spec = EnglishArcadeCurriculum.mock(mock_id)
    post "/english-arcade/sessions", params: {
      english_arcade_session: { mock_id: mock_id, target: spec.fetch("target"), mode: spec.fetch("mode"), card_key: spec.fetch("required_card_keys").first, exercise: "initial" }
    }
    assert_response :redirect
    EnglishArcadeSession.order(:id).last
  end

  def meaningful_typed_answer
    "I would state the decision, name the trade-off, verify the boundary, and explain the evidence I would inspect before changing the implementation."
  end

  def meaningful_feynman_answer
    "I chose this option because it names the invariant, explains the trade-off, and gives me a concrete signal to verify before making the next decision."
  end

  def self_rubric_params
    {
      english_directness: "english_direct", self_clarity: 3, self_precision: 3,
      self_naturalness: 3, self_pragmatic_appropriateness: 3, self_technical_correctness: 3,
      problem_frame: "The interviewer needs a bounded decision for the stated input and workload.",
      evidence_verified: "The authored prompt establishes the input boundary.",
      evidence_inference: "The invariant follows from that boundary.",
      evidence_assumption: "The workload remains within the stated operational limit.",
      evidence_gap: "Production scale still needs measurement.",
      source_quality: "The authored prompt is primary; runtime evidence is still pending.",
      comparison_option_a: "Keep the simple implementation.",
      comparison_option_b: "Use indexed state.",
      comparison_tradeoff: "Memory buys fewer scans.",
      comparison_switch_condition: "Switch when measured load crosses the bound.",
      comparison_rejected_alternative: "The alternative violates the same input contract.",
      comparison_hard_constraint: "The input contract is fixed.",
      comparison_decision_rule: "Clarify the contract before comparing.",
      counterexample: "An adversarial duplicate can invalidate the assumed bound.",
      change_my_mind: "A measured trace that breaks the bound would change my recommendation.",
      confidence_percent: 70
    }
  end

  def critical_artifact_params(card)
    base = {
      problem_frame: "The interviewer needs a bounded decision for the stated input and workload.",
      evidence_verified: "The authored prompt establishes the input boundary.",
      evidence_inference: "The invariant follows from that boundary.",
      evidence_assumption: "The workload remains within the stated operational limit.",
      evidence_gap: "Production scale still needs measurement.",
      source_quality: "The authored prompt is primary; runtime evidence is still pending.",
      counterexample: "An adversarial duplicate can invalidate the assumed bound.",
      change_my_mind: "A measured trace that breaks the bound would change my recommendation.",
      confidence_percent: 70
    }
    if card.critical_thinking.dig("comparison", "applicable") == true
      base.merge(comparison_option_a: "Keep the simple implementation.", comparison_option_b: "Use indexed state.", comparison_tradeoff: "Memory buys fewer scans.", comparison_switch_condition: "Switch when measured load crosses the bound.")
    else
      base.merge(comparison_rejected_alternative: "The alternative violates the same input contract.", comparison_hard_constraint: "The input contract is fixed.", comparison_decision_rule: "Clarify the contract before comparing.")
    end
  end

  def revealed_attempt(english_arcade_session:, card_key:, learner_key: "anonymous", target: "dsa", correct: true, state: "scheduled", answered_at: Time.current)
    card = @builder.card_for(target: target, card_key: card_key, session: english_arcade_session, variant_id: "initial")
    if card
      artifact_payload = {
        problem_frame: "The interviewer needs a bounded decision for the stated input and workload.",
        evidence_verified: "The authored prompt establishes the input boundary.",
        evidence_inference: "The invariant follows from that boundary.",
        evidence_assumption: "The workload remains within the stated operational limit.",
        evidence_gap: "Production scale still needs measurement.",
        source_quality: "The authored prompt is primary; runtime evidence is still pending.",
        counterexample: "An adversarial duplicate can invalidate the assumed bound.",
        change_my_mind: "A measured trace that breaks the bound would change my recommendation.",
        confidence_percent: 70
      }
      if card.critical_thinking.dig("comparison", "applicable") == true
        artifact_payload.merge!(comparison_option_a: "Keep the simple implementation.", comparison_option_b: "Use indexed state.", comparison_tradeoff: "Memory buys fewer scans.", comparison_switch_condition: "Switch when measured load crosses the bound.")
      else
        artifact_payload.merge!(comparison_rejected_alternative: "The alternative violates the same input contract.", comparison_hard_constraint: "The input contract is fixed.", comparison_decision_rule: "Clarify the contract before comparing.")
      end
      artifact = EnglishArcadeAttemptContract.artifact_from(artifact_payload, critical_thinking: card.critical_thinking)
      assessment = EnglishArcadeAttemptContract.frozen_contract(card.variant_contract, content_version: card.content_version).merge(
        "contract_version" => EnglishArcadeAttemptContract::CONTRACT_VERSION,
        "variant_id" => card.variant_id,
        "variant_digest" => card.variant_digest,
        "content_version" => card.content_version,
        "correct" => correct,
        "selected_choice" => card.correct_choice,
        "critical_thinking" => card.critical_thinking
      )
      return EnglishArcadeAttempt.create!(
        english_arcade_session: english_arcade_session,
        learner_key: learner_key,
        target: target,
        card_key: card_key,
        attempt_kind: "initial",
        variant_key: "initial",
        answer_choice: card.correct_choice,
        typed_answer: meaningful_typed_answer,
        correct: correct,
        feedback_revealed: true,
        state: state,
        quality_score: correct ? 9 : 0,
        box_before: 1,
        box_after: correct ? 2 : 1,
        answered_at: answered_at,
        feynman_text: meaningful_feynman_answer,
        diagnostic_evidence: {
          "assessment_scope" => "server_contract", "production" => { "typed_length" => meaningful_typed_answer.length },
          "feynman_present" => true, "critical_artifact" => artifact, "assessment" => assessment
        },
        prompt_snapshot: @builder.prompt_snapshot(card)
      )
    end

    EnglishArcadeAttempt.create!(
      english_arcade_session: english_arcade_session,
      learner_key: learner_key,
      target: target,
      card_key: card_key,
      attempt_kind: "initial",
      typed_answer: meaningful_typed_answer,
      correct: correct,
      feedback_revealed: true,
      state: state,
      box_before: 1,
      box_after: correct ? 2 : 1,
      answered_at: answered_at,
      diagnostic_evidence: {}
    )
  end

  def complete_black_box!(attempt)
    attempt.update!(
      state: "scheduled",
      black_box_root_cause: "The initial constraint was not stated before choosing the design.",
      black_box_missing_signal: "The observable failure signal was absent from the reasoning.",
      black_box_preventive_rule: "State the invariant and the failure signal before committing.",
      black_box_targeted_exercise: "Rehearse the same card with a named observable boundary.",
      black_box_retest_dates: "Retry tomorrow and repeat the review in seven days."
    )
  end

  def assert_adaptive_launch_rejected(item_id)
    before = EnglishArcadeSession.count
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily", card_key: item_id, exercise: "follow_up" }
    }
    assert_response :redirect
    assert_equal before, EnglishArcadeSession.count
    assert_includes flash[:alert], "latest revealed attempt"
  end

  def commit_and_reveal(session, card, exercise: nil)
    card = @builder.card_for(target: card.target, card_key: card.key, session: session, variant_id: card.variant_id)
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, exercise: exercise, answer_choice: card.correct_choice, typed_answer: meaningful_typed_answer, **self_rubric_params }
    }
    attempt = EnglishArcadeAttempt.order(:id).last
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: meaningful_feynman_answer }
    }
    assert_predicate attempt.reload, :feedback_revealed?
    attempt
  end

  def commit_wrong_and_complete_black_box(session, card)
    card = @builder.card_for(target: card.target, card_key: card.key, session: session, variant_id: card.variant_id)
    wrong_choice = card.options.find { |choice| choice.id != card.correct_choice }
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: wrong_choice.id, typed_answer: meaningful_typed_answer, **self_rubric_params }
    }
    attempt = EnglishArcadeAttempt.order(:id).last
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { attempt_id: attempt.id, phase: "feynman", feynman_text: meaningful_feynman_answer }
    }
    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: black_box_params(attempt.id)
    }
    attempt.reload
  end

  def complete_mock_phases(session, mock_id)
    spec = EnglishArcadeCurriculum.mock(mock_id)
    current = session.reload.started_at
    spec.fetch("phases").each_with_index do |phase, index|
      current += (phase.fetch("minutes").to_i * 60 * 0.9 + 1).ceil.seconds
      travel_to(current) do
        post "/english-arcade/attempts", params: {
          session_id: session.id,
          english_arcade_attempt: {
            phase: "mock_phase", phase_id: phase.fetch("id"),
            phase_artifact: "A typed #{phase.fetch('id')} artifact states the contract, evidence, edge case, and verification signal for this scenario."
          }
        }, as: :json
        assert_response :success, "phase #{index}: #{response.body}"
      end
      next_phase_start = session.reload.metadata.dig("phase_state", "current_phase_started_at")
      current = Time.iso8601(next_phase_start) if next_phase_start
    end
    current
  end

  def assert_required_mock_locked(session, card_key)
    before = EnglishArcadeAttempt.count
    post "/english-arcade/attempts", params: { session_id: session.id, english_arcade_attempt: { card_key: card_key, answer_choice: "a", typed_answer: meaningful_typed_answer, **self_rubric_params } }
    assert_response :redirect
    assert_equal before, EnglishArcadeAttempt.count
    assert_includes flash[:alert], "Complete the current required card"
  end

  def assert_required_mock_finish_blocked(session)
    post finish_english_arcade_path, params: { session_id: session.id }
    assert_response :redirect
    assert_equal "active", session.reload.status
    assert_includes flash[:alert], "Complete every required card in order"
  end

  def black_box_params(attempt_id)
    {
      attempt_id: attempt_id, phase: "postmortem",
      black_box_root_cause: "I chose an answer before identifying the requested behavioural evidence.",
      black_box_missing_signal: "The required STAR outcome and stakeholder impact were not named.",
      black_box_preventive_rule: "State the requested interview structure before choosing the response.",
      black_box_targeted_exercise: "Rehearse the same scenario with a visible STAR outline first.",
      black_box_retest_dates: "Retry tomorrow and repeat this exercise after seven days."
    }
  end
end

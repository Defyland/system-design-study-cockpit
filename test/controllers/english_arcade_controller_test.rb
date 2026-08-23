require "test_helper"

class EnglishArcadeControllerTest < ActionDispatch::IntegrationTest
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
    assert payload.fetch("thirty_day_plan").all? { |day| day.key?("interleaving") && day.key?("weak_area_remediation") }
    progress = payload.fetch("progress_30_days")
    assert_equal "not_assessed", progress.fetch("skill_evidence").fetch("listening").fetch("status")
    assert progress.fetch("feedback_evidence").key?("register")
    assert_equal 0, progress.fetch("capture_evidence").fetch("typed_count")

    session = start_session
    get "/english-arcade.json", params: { session_id: session.id }
    active_payload = JSON.parse(response.body)
    assert_predicate active_payload.fetch("cards"), :any?
    refute active_payload.to_json.include?("correct_choice")
    refute active_payload.to_json.include?("answer_text")
  end

  test "an error requires five actionable Black Box fields before scheduling" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1).cards.first

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        card_key: card.key,
        answer_choice: "b",
        attempt_kind: "initial"
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
        feynman_text: "I compared the boundary and named the trade-off."
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

  test "skip is a persisted incorrect branch and cannot reveal without Feynman" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1).cards.first

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
      english_arcade_attempt: { attempt_id: attempt.id, card_key: card.key, phase: "feynman", feynman_text: "I could not name the invariant yet." }
    }
    attempt.reload
    assert_equal "feedback", attempt.state
    refute attempt.correct?
    assert_equal 0, EnglishArcadeCard.find_by!(learner_key: "anonymous", target: "dsa", card_key: card.key).attempts_count
  end

  test "JSON Black Box completion returns scheduling evidence without answer metadata" do
    session = start_session
    card = @builder.call(target: "dsa", learner_key: "anonymous", limit: 1).cards.first

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: { card_key: card.key, answer_choice: "b", attempt_kind: "initial" }
    }, as: :json
    attempt_id = JSON.parse(response.body).fetch("attempt_id")

    post "/english-arcade/attempts", params: {
      session_id: session.id,
      english_arcade_attempt: {
        attempt_id: attempt_id,
        card_key: card.key,
        phase: "feynman",
        feynman_text: "I named the missing boundary and the trade-off before choosing."
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

  private

  def start_session
    post "/english-arcade/sessions", params: {
      english_arcade_session: { target: "dsa", mode: "daily" }
    }
    assert_response :see_other
    EnglishArcadeSession.order(:id).last
  end
end

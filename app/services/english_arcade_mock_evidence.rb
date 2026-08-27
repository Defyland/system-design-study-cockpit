# frozen_string_literal: true

# One fail-closed implementation of the timed-mock contract. The controller
# uses this before finishing a session and the progress report uses the same
# service when aggregating official mock evidence.
class EnglishArcadeMockEvidence
  MIN_TYPED_PRODUCTION_LENGTH = 40
  COMPLETED_STATES = %w[scheduled mastered revealed].freeze

  class << self
    def for(session:, now: Time.current)
      spec = EnglishArcadeCurriculum.mock(session.metadata.to_h["mock_id"])
      return failure("unregistered_mock") unless spec
      return failure("session_not_completed") unless session.active? || session.completed?
      return failure("incompatible_session") unless compatible?(session, spec)
      return failure("phase_ledger_invalid") unless phases_valid?(session, spec, now)

      started_at = session.started_at
      finished_at = session.finished_at || now
      elapsed = started_at && finished_at ? finished_at - started_at : nil
      required_seconds = session.duration_seconds.to_i * 9 / 10
      return failure("timed_window_incomplete", elapsed_seconds: elapsed, required_seconds: required_seconds) unless elapsed && elapsed >= required_seconds

      attempts = session.english_arcade_attempts.order(:answered_at, :id).to_a
      sequence = Array(spec["required_sequence"])
      return failure("sequence_shape_missing") if sequence.empty?
      return failure("sequence_shape_invalid") unless sequence_shape_valid?(sequence, spec)
      return failure("sequence_length") unless attempts.length == sequence.length

      evidence = sequence.each_with_index.map do |step, index|
        attempt = attempts.fetch(index)
        prior = index.zero? ? nil : attempts.fetch(index - 1)
        return failure("sequence_mismatch", step: index) unless step_matches?(attempt, step, session, spec, started_at, finished_at)
        if step["attempt_kind"].to_s == "follow_up"
          return failure("follow_up_parent_mismatch", step: index) unless prior && attempt.parent_attempt_id.to_i == prior.id.to_i
          return failure("follow_up_not_correct", step: index) unless attempt.correct?
          return failure("follow_up_variant_not_distinct", step: index) if same_variant_digest?(prior, attempt)
        else
          return failure("initial_not_defensible", step: index) unless attempt.correct? || attempt.black_box_complete?
        end
        return failure("critical_artifact_missing", step: index) unless attempt.critical_eligible?
        return failure("feynman_missing", step: index) unless meaningful_feynman?(attempt)
        return failure("typed_production_missing", step: index) unless meaningful_production?(attempt)

        {
          "step" => index,
          "attempt_id" => attempt.id,
          "card_key" => attempt.card_key,
          "attempt_kind" => attempt.attempt_kind,
          "variant_id" => attempt.diagnostic_evidence.dig("assessment", "variant_id").to_s,
          "content_variant_id" => attempt.diagnostic_evidence.dig("assessment", "variant_id").to_s,
          "correct" => attempt.correct?
        }
      end

      {
        "qualifying" => true,
        "id" => spec.fetch("id"),
        "target" => session.target,
        "day" => spec.fetch("day"),
        "elapsed_seconds" => elapsed.to_f,
        "required_seconds" => required_seconds,
        "required_card_keys" => Array(spec.fetch("required_card_keys")),
        "required_sequence" => sequence,
        "sequence" => evidence,
        "ratio" => (elapsed.to_f / session.duration_seconds.to_f).round(3)
      }
    rescue ActiveRecord::RecordNotFound, KeyError, NoMethodError, TypeError
      failure("invalid_mock_record")
    end

    def qualifying?(session:, now: Time.current)
      self.for(session: session, now: now).fetch("qualifying", false)
    end

    private

    def failure(reason, **details)
      { "qualifying" => false, "reason" => reason }.merge(details.stringify_keys)
    end

    def compatible?(session, spec)
      metadata = session.metadata.to_h.stringify_keys
      session.target == spec.fetch("target") &&
        session.mode == spec.fetch("mode") &&
        session.duration_seconds.to_i == spec.fetch("duration_minutes").to_i * 60 &&
        metadata["curriculum_day"].to_i == spec.fetch("day").to_i &&
        metadata["exercise"].to_s == "initial" &&
        metadata.key?("scheduled_card_key") && metadata["scheduled_card_key"].nil? &&
        Array(metadata["required_card_keys"]) == Array(spec.fetch("required_card_keys")) &&
        metadata["content_version"].to_s.present? && metadata["content_version"].to_s != "unknown"
    end

    def phases_valid?(session, spec, now)
      return false if Array(spec["phases"]).empty?

      EnglishArcadeCurriculum.phase_state_valid?(
        spec,
        session.metadata.to_h.stringify_keys["phase_state"],
        session_started_at: session.started_at,
        expires_at: session.expires_at,
        now: session.finished_at || now
      )
    end

    def step_matches?(attempt, step, session, spec, started_at, finished_at)
      expected_target = EnglishArcadeCurriculum.target_for(step.fetch("card_key"))
      expected_target ||= spec.fetch("target")
      attempt.english_arcade_session_id == session.id &&
        attempt.learner_key == session.learner_key &&
        attempt.card_key.to_s == step.fetch("card_key").to_s &&
        attempt.attempt_kind.to_s == step.fetch("attempt_kind").to_s &&
        attempt.variant_key.to_s == variant_id_for(step).to_s &&
        attempt.target.to_s == expected_target.to_s &&
        attempt.feedback_revealed? &&
        COMPLETED_STATES.include?(attempt.state.to_s) &&
        attempt.answered_at && started_at && finished_at &&
        attempt.answered_at >= started_at && attempt.answered_at <= finished_at &&
        !%w[skip reset error].include?(attempt.diagnostic_evidence["answer_status"].to_s) &&
        !%w[skip reset error].include?(attempt.diagnostic_evidence["outcome"].to_s) &&
        frozen_snapshot_valid?(attempt, step)
    end

    def frozen_snapshot_valid?(attempt, step)
      assessment = attempt.diagnostic_evidence.to_h.fetch("assessment", {}).to_h
      snapshot = attempt.prompt_snapshot.to_h
      option_ids = Array(snapshot["options"]).map { |option| option.to_h["id"].to_s }
      selected_choice = attempt.diagnostic_evidence.to_h["selected_choice"].presence || assessment["selected_choice"]
      snapshot["contract_version"].to_s == "arcade-attempt-v1" &&
        snapshot["variant_id"].to_s == variant_id_for(step).to_s &&
        snapshot["variant_digest"].to_s == assessment["variant_digest"].to_s &&
        snapshot["content_version"].to_s == assessment["content_version"].to_s &&
        assessment["variant_id"].to_s == variant_id_for(step).to_s &&
        assessment["correct"].in?([ true, false ]) && assessment["correct"] == attempt.correct? &&
        option_ids.length >= 2 && option_ids.include?(attempt.answer_choice.to_s) &&
        selected_choice.to_s == attempt.answer_choice.to_s &&
        assessment["correct_choice"].to_s.in?(option_ids)
    end

    def meaningful_feynman?(attempt)
      attempt.diagnostic_evidence["feynman_present"] == true &&
        attempt.feynman_text.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH
    end

    def meaningful_production?(attempt)
      attempt.typed_answer.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH &&
        attempt.diagnostic_evidence.dig("production", "typed_length").to_i >= MIN_TYPED_PRODUCTION_LENGTH
    end

    def variant_id_for(step)
      step["content_variant_id"].presence || step.fetch("variant_id")
    end

    def sequence_shape_valid?(sequence, spec)
      required_keys = Array(spec["required_card_keys"])
      return false unless sequence.length == required_keys.length * 2

      sequence.each_with_index.all? do |step, index|
        expected_kind = index.even? ? "initial" : "follow_up"
        expected_parent_step = index.even? ? nil : index - 1
        step.is_a?(Hash) &&
          step["card_key"].to_s == required_keys.fetch(index / 2).to_s &&
          step["attempt_kind"].to_s == expected_kind &&
          step["content_variant_id"].to_s.in?(%w[initial follow_up]) &&
          step["parent_step"] == expected_parent_step
      end
    rescue IndexError, NoMethodError, TypeError
      false
    end

    def same_variant_digest?(first, second)
      first_digest = first.diagnostic_evidence.to_h.dig("assessment", "variant_digest").to_s
      second_digest = second.diagnostic_evidence.to_h.dig("assessment", "variant_digest").to_s
      first_digest.present? && second_digest.present? && first_digest == second_digest
    end
  end
end

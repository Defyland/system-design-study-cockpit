# frozen_string_literal: true

# One server-owned eligibility boundary for evidence that may affect critical
# thinking metrics, adaptation lineage, and mastery. Learner self-ratings are
# deliberately absent from this service: they are report-only observations.
require_relative "english_arcade_attempt_contract"

class EnglishArcadeEvidenceEligibility
  MIN_TYPED_PRODUCTION_LENGTH = 40
  # Only the authored question, its adversarial follow-up, and the delayed
  # retention variant are strong enough to affect critical-thinking gates or
  # mastery. Rephrases/compressions/extensions remain useful practice, but are
  # deliberately report-only adaptations.
  CRITICAL_VARIANTS = EnglishArcadeAttemptContract::CRITICAL_VARIANT_IDS.freeze

  class << self
    def critical?(attempt)
      return false unless attempt
      return false unless attempt.feedback_revealed?
      return false unless attempt.critical_artifact_complete?
      return false unless attempt.typed_answer.to_s.strip.length >= MIN_TYPED_PRODUCTION_LENGTH
      return false if attempt.spoken_text.present?
      return false unless attempt.attempt_kind.to_s.in?(EnglishArcadeAttempt::ATTEMPT_KINDS)

      assessment = assessment_for(attempt)
      return false unless assessment.is_a?(Hash)
      return false unless assessment["variant_id"].to_s == attempt.variant_key.to_s
      return false unless CRITICAL_VARIANTS.include?(assessment["variant_id"].to_s)
      return false unless assessment["variant_digest"].to_s.present?
      return false unless assessment["content_version"].to_s.present? && assessment["content_version"].to_s != "unknown"
      return false unless assessment["contract_version"].to_s == EnglishArcadeAttemptContract::CONTRACT_VERSION
      return false unless assessment["correct"].in?([ true, false ])
      return false unless attempt.correct? == assessment["correct"]
      return false unless frozen_snapshot_matches?(attempt, assessment)
      return false unless attempt.diagnostic_evidence.to_h["assessment_scope"].to_s == "server_contract"

      true
    rescue NoMethodError, TypeError
      false
    end

    def mastery?(attempt)
      critical?(attempt) && attempt.correct? && attempt.quality_score.to_i >= 8
    end

    def assessment_for(attempt)
      attempt.diagnostic_evidence.to_h.fetch("assessment", {}).to_h
    end

    def frozen_snapshot_matches?(attempt, assessment)
      snapshot = attempt.prompt_snapshot.to_h
      options = Array(snapshot["options"]).filter_map { |option| option.to_h["id"].to_s.presence }
      selected_choice = attempt.diagnostic_evidence.to_h["selected_choice"].presence || assessment["selected_choice"]
      forbidden = %w[answer_text correct_choice feedback check critical_thinking follow_up_prompt rephrase_prompt compression_prompt extension_prompt]
      snapshot["contract_version"].to_s == EnglishArcadeAttemptContract::CONTRACT_VERSION &&
        forbidden.none? { |key| snapshot.key?(key) } &&
        snapshot["variant_id"].to_s == assessment["variant_id"].to_s &&
        snapshot["variant_digest"].to_s == assessment["variant_digest"].to_s &&
        snapshot["content_version"].to_s == assessment["content_version"].to_s &&
        options.length >= 2 && options.uniq.length == options.length &&
        options.include?(attempt.answer_choice.to_s) &&
        selected_choice.to_s == attempt.answer_choice.to_s &&
        assessment["correct_choice"].to_s.in?(options)
    end

    # Server-side parent gate used by both adaptive launch and attempt
    # commit. It deliberately accepts a parent from an earlier session while
    # requiring the learner/target/card identity and a genuinely distinct
    # authored variant. Delayed retry adds the seven-day condition here so the
    # controller cannot accidentally create a same-day retention event.
    def adaptation_parent?(parent, learner_key:, target:, card_key:, child_variant_id:, child_digest:, kind:)
      return false unless parent
      return false unless parent.feedback_revealed?
      return false unless parent.learner_key.to_s == learner_key.to_s
      return false unless parent.target.to_s == target.to_s
      return false unless parent.card_key.to_s == card_key.to_s
      return false unless parent.english_arcade_session&.learner_key.to_s == learner_key.to_s
      return false unless critical?(parent)
      return false unless parent.correct? || parent.black_box_complete?

      parent_assessment = assessment_for(parent)
      parent_variant = parent_assessment["variant_id"].to_s
      parent_digest = parent_assessment["variant_digest"].to_s
      return false if parent_variant.blank? || parent_digest.blank?
      return false if parent_variant == child_variant_id.to_s
      return false if parent_digest == child_digest.to_s
      return false if kind.to_s == "retry" && (parent_variant != "initial" || parent.answered_at.blank? || parent.answered_at > 7.days.ago)

      true
    rescue NoMethodError, TypeError
      false
    end

    def same_lineage?(child, parent, require_critical: true)
      return false unless child && parent
      return false unless child.parent_attempt_id.to_i == parent.id.to_i
      return false unless child.learner_key.to_s == parent.learner_key.to_s
      return false unless child.target.to_s == parent.target.to_s
      return false unless child.card_key.to_s == parent.card_key.to_s
      return false unless child.english_arcade_session&.learner_key.to_s == child.learner_key.to_s
      return false unless parent.english_arcade_session&.learner_key.to_s == parent.learner_key.to_s
      return false unless parent.feedback_revealed?
      return false unless child.answered_at && parent.answered_at && parent.answered_at <= child.answered_at
      return false if require_critical && (!critical?(parent) || !critical?(child))
      return false if child.variant_key.to_s == parent.variant_key.to_s
      return false if assessment_for(child)["variant_digest"].to_s == assessment_for(parent)["variant_digest"].to_s

      true
    rescue NoMethodError, TypeError
      false
    end
  end
end

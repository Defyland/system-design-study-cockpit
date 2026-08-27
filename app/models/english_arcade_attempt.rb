class EnglishArcadeAttempt < ApplicationRecord
  require_relative "../services/english_arcade_attempt_contract"
  require_relative "../services/english_arcade_evidence_eligibility"
  ATTEMPT_KINDS = %w[initial retry rephrase extension follow_up compression].freeze
  STATES = %w[idle active_recall committed feynman feedback black_box scheduled reattempt mastered revealed].freeze
  BLACK_BOX_FIELDS = %w[root_cause missing_signal preventive_rule targeted_exercise retest_dates].freeze
  BLACK_BOX_MIN_LENGTH = 8
  VAGUE_BLACK_BOX = /\A(?:i(?:\s+just)?\s+)?(?:didn't|did not|don't|do not)\s+know\.?\z|\A(?:i\s+have\s+)?(?:no idea|no clue)\.?\z|\A(?:idk|not sure|n\/a|none|unknown)\.?\z/i

  belongs_to :english_arcade_session
  belongs_to :parent_attempt, class_name: "EnglishArcadeAttempt", optional: true
  has_many :follow_up_attempts, class_name: "EnglishArcadeAttempt", foreign_key: :parent_attempt_id, dependent: :nullify

  validates :learner_key, :target, :card_key, :attempt_kind, :answered_at, presence: true
  validates :attempt_kind, inclusion: { in: ATTEMPT_KINDS }
  validates :state, inclusion: { in: STATES }
  validates :correct, inclusion: { in: [ true, false ] }
  validates :quality_score, numericality: { only_integer: true, in: 0..10 }
  validate :answer_payload_present
  validate :feedback_must_follow_answer

  scope :recent_first, -> { order(answered_at: :desc) }

  def critical_artifact
    diagnostic_evidence.to_h.fetch("critical_artifact", {})
  end

  def critical_artifact_complete?
    artifact = critical_artifact.to_h
    assessment = diagnostic_evidence.to_h.fetch("assessment", {}).to_h
    authored_applicable = assessment.dig("critical_thinking", "comparison", "applicable")
    classifications = artifact.fetch("learner_classifications", {}).to_h
    comparison = artifact.fetch("comparison", {}).to_h
    branch_complete = if authored_applicable == true
      comparison["authored_applicable"] == true &&
        comparison["comparison_option_a"].to_s.strip.length >= 8 &&
        comparison["comparison_option_b"].to_s.strip.length >= 8 &&
        normalize_critical_text(comparison["comparison_option_a"]) != normalize_critical_text(comparison["comparison_option_b"]) &&
        comparison["comparison_tradeoff"].to_s.strip.length >= 8 &&
        comparison["comparison_switch_condition"].to_s.strip.length >= 8
    elsif authored_applicable == false
      comparison["authored_applicable"] == false &&
        comparison["comparison_rejected_alternative"].to_s.strip.length >= 8 &&
        comparison["comparison_hard_constraint"].to_s.strip.length >= 8 &&
        comparison["comparison_decision_rule"].to_s.strip.length >= 8
    else
      false
    end
    artifact["complete"] == true && artifact["captured_before_reveal"] == true &&
      %w[evidence_verified evidence_inference evidence_assumption evidence_gap].all? { |key| classifications[key].to_s.strip.length >= 8 } &&
      branch_complete && artifact["counterexample"].to_s.strip.length >= 8 &&
      artifact["change_my_mind"].to_s.strip.length >= 8 &&
      artifact["confidence_percent"].is_a?(Numeric) && artifact["confidence_percent"].between?(0, 100) &&
      artifact.dig("fact_contract_accuracy", "source").to_s == "authored_reference" &&
      artifact.dig("fact_contract_accuracy", "assessment_scope").to_s == "not_assessed" &&
      artifact.dig("semantic_quality", "source").to_s == "not_assessed" &&
      artifact.dig("semantic_quality", "assessment_scope").to_s == "not_assessed"
  end

  def critical_eligible?
    EnglishArcadeEvidenceEligibility.critical?(self)
  end

  def normalize_critical_text(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
  end
  private :normalize_critical_text

  private

  def answer_payload_present
    return if answer_choice.present? || typed_answer.present? || spoken_text.present?

    errors.add(:base, "an answer choice or text capture is required")
  end

  def feedback_must_follow_answer
    return unless feedback_revealed || state == "revealed"
    return if answered_at.present? && correct.in?([ true, false ])

    errors.add(:feedback_revealed, "cannot be revealed before an answered attempt")
  end

  public

  def black_box_fields
    {
      "root_cause" => black_box_root_cause,
      "missing_signal" => black_box_missing_signal,
      "preventive_rule" => black_box_preventive_rule,
      "targeted_exercise" => black_box_targeted_exercise,
      "retest_dates" => black_box_retest_dates
    }
  end

  def missing_black_box_fields
    black_box_fields.filter_map { |field, value| field unless value.to_s.strip.present? }
  end

  def black_box_complete?
    missing_black_box_fields.empty? && black_box_fields.values.all? { |value| value.to_s.strip.length >= BLACK_BOX_MIN_LENGTH } && !black_box_vague?
  end

  def black_box_vague?
    black_box_fields.values.any? do |value|
      value.to_s.strip.match?(VAGUE_BLACK_BOX)
    end
  end
end

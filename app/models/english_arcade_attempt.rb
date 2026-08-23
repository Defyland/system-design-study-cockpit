class EnglishArcadeAttempt < ApplicationRecord
  ATTEMPT_KINDS = %w[initial retry rephrase extension].freeze
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

class EnglishArcadeCard < ApplicationRecord
  require_relative "../services/english_arcade_attempt_contract"
  BOX_INTERVALS = {
    1 => 1,
    2 => 2,
    3 => 4,
    4 => 7,
    5 => 14
  }.freeze

  validates :learner_key, :target, :card_key, :due_on, presence: true
  validates :box, inclusion: { in: BOX_INTERVALS.keys }
  validates :interval_days, inclusion: { in: BOX_INTERVALS.values }
  validates :card_key, uniqueness: { scope: %i[learner_key target] }

  scope :due, ->(on = Date.current) { where("due_on <= ?", on).order(:due_on, :updated_at) }
  scope :for_learner, ->(learner_key) { where(learner_key: learner_key) }
  scope :for_target, ->(target) { where(target: target) }

  def self.mastered_keys_for(learner_key)
    attempts = EnglishArcadeAttempt
      .where(learner_key: learner_key)
      .order(:target, :card_key, :answered_at)
      .to_a
      .select { |attempt| EnglishArcadeAttemptContract.mastery_eligible?(attempt) }

    attempts.group_by { |attempt| [ attempt.target, attempt.card_key ] }.filter_map do |key, high_quality|
      key if spaced_variant_pair?(high_quality)
    end
  end

  def self.spaced_variant_pair?(attempts)
    attempts.sort_by(&:answered_at).combination(2).any? do |first, second|
      first.variant_key.to_s.in?(EnglishArcadeAttemptContract::CRITICAL_VARIANT_IDS) &&
        second.variant_key.to_s.in?(EnglishArcadeAttemptContract::CRITICAL_VARIANT_IDS) &&
        first.variant_key.to_s != second.variant_key.to_s &&
        first.diagnostic_evidence.dig("assessment", "variant_digest").to_s.present? &&
        second.diagnostic_evidence.dig("assessment", "variant_digest").to_s.present? &&
        first.diagnostic_evidence.dig("assessment", "variant_digest").to_s != second.diagnostic_evidence.dig("assessment", "variant_digest").to_s &&
        (second.answered_at - first.answered_at) >= 7.days
    end
  end

  def due?(on = Date.current)
    due_on <= on
  end

  def interval_label
    case interval_days
    when 1 then "daily"
    when 2 then "2-day"
    when 4 then "4-day"
    when 7 then "weekly"
    when 14 then "2-weekly"
    else "#{interval_days}-day"
    end
  end

  # Leitner transition: a miss always returns to box 1; a correct answer
  # advances one box and schedules the next interval from the new box.
  def record!(correct:, at: Time.current)
    next_box = correct ? [ box + 1, BOX_INTERVALS.keys.max ].min : BOX_INTERVALS.keys.min
    next_interval = BOX_INTERVALS.fetch(next_box)

    self.box = next_box
    self.interval_days = next_interval
    self.due_on = at.to_date + next_interval.days
    self.attempts_count += 1
    self.correct_count += 1 if correct
    self.last_correct = correct
    self.last_answered_at = at
    save!
    self
  end

  # Sol's mastery gate: two high-quality attempts on different variants with
  # at least seven days between them. A calendar-week boundary is part of the
  # contract, so a six-day sprint cannot be counted as spaced mastery.
  def mastery_attempts
    EnglishArcadeAttempt.where(
      learner_key: learner_key,
      target: target,
      card_key: card_key
    ).order(:answered_at).to_a.select { |attempt| EnglishArcadeAttemptContract.mastery_eligible?(attempt) }
  end

  def mastered?
    self.class.spaced_variant_pair?(mastery_attempts)
  end

  def mastery_progress
    high_quality = mastery_attempts.to_a
    spaced_pair = high_quality.sort_by(&:answered_at).combination(2).find do |first, second|
      first.variant_key.to_s.in?(EnglishArcadeAttemptContract::CRITICAL_VARIANT_IDS) &&
        second.variant_key.to_s.in?(EnglishArcadeAttemptContract::CRITICAL_VARIANT_IDS) &&
        first.variant_key.to_s != second.variant_key.to_s &&
        first.diagnostic_evidence.dig("assessment", "variant_digest").to_s.present? &&
        second.diagnostic_evidence.dig("assessment", "variant_digest").to_s.present? &&
        first.diagnostic_evidence.dig("assessment", "variant_digest").to_s != second.diagnostic_evidence.dig("assessment", "variant_digest").to_s &&
        (second.answered_at - first.answered_at) >= 7.days
    end

    {
      "high_quality_attempts" => high_quality.length,
      "spaced_variants" => high_quality.map(&:variant_key).uniq.length,
      "mastered" => spaced_pair.present?,
      "next_spacing_days" => spaced_pair ? 0 : 7
    }
  end
end

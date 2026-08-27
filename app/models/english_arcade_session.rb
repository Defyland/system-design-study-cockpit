require_relative "../../lib/english_arcade/schema"

class EnglishArcadeSession < ApplicationRecord
  # Keep persisted values aligned with the pack schema. `mixed` and `interview`
  # are launcher modes over the thirteen canonical packs, rather than packs of
  # their own; Salesforce stays selectable but elective.
  TARGETS = (EnglishArcade::Schema::TARGETS + %w[mixed interview]).freeze

  MODES = %w[daily timed_30 timed_45].freeze
  STATUSES = %w[active completed expired cancelled].freeze

  enum :mode, MODES.index_with(&:to_s), validate: true
  enum :status, STATUSES.index_with(&:to_s), validate: true

  has_many :english_arcade_attempts, dependent: :destroy

  validates :learner_key, :target, :mode, :status, :started_at, presence: true
  validates :target, inclusion: { in: TARGETS }
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_learner, ->(learner_key) { where(learner_key: learner_key) }

  def expired?(at: Time.current)
    expires_at.present? && expires_at <= at
  end

  def remaining_seconds(at: Time.current)
    return 0 if expired?(at: at)
    return duration_seconds if expires_at.blank?

    [ (expires_at - at).ceil, 0 ].max
  end

  def complete!(at: Time.current)
    update!(status: :completed, finished_at: at)
  end

  def expire!(at: Time.current)
    update!(status: :expired, finished_at: at)
  end
end

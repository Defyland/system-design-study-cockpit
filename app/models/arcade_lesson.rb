class ArcadeLesson < ApplicationRecord
  TARGET_MODES = %w[single mixed interview card].freeze
  STATUSES = %w[active finished abandoned].freeze

  enum :target_mode, TARGET_MODES.index_with(&:to_s), validate: true
  enum :status, STATUSES.index_with(&:to_s), validate: true

  has_many :arcade_exercise_events, dependent: :destroy

  validates :learner_key, :target_mode, :target, :seed, :started_at, presence: true
  validates :target_mode, inclusion: { in: TARGET_MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :exercises_total, :exercises_done, :correct_count, :new_cards_count, :review_count,
            :boss_correct, :boss_total, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_learner, ->(learner_key) { where(learner_key: learner_key) }
  scope :recent_first, -> { order(started_at: :desc, id: :desc) }

  def active?
    status == "active"
  end

  def complete!
    update!(status: :finished, finished_at: Time.current)
  end
end

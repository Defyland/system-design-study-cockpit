class ArcadeStageState < ApplicationRecord
  STAGES = %w[meet recognize trap cloze rebuild produce speak transfer compress feynman].freeze
  STATUSES = %w[new learning review relearning].freeze

  enum :status, STATUSES.index_with(&:to_s), prefix: true, validate: true

  validates :learner_key, :target, :card_key, :stage, :content_version, :due_at, presence: true
  validates :stage, inclusion: { in: STAGES }
  validates :stability, :difficulty, numericality: true
  validates :difficulty, numericality: { in: 1..10 }
  validates :reps, :lapses, :streak, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :card_key, uniqueness: { scope: %i[learner_key stage] }

  scope :for_learner, ->(learner_key) { where(learner_key: learner_key) }
  scope :due, ->(at = Time.current) { where("due_at <= ?", at).order(:due_at, :id) }
  scope :for_target, ->(target) { where(target: target) }

  def due?(at = Time.current)
    due_at <= at
  end
end

class ArcadeExerciseEvent < ApplicationRecord
  AXES = %w[register hedging precision grammar pragmatics content].freeze

  belongs_to :arcade_lesson

  validates :learner_key, :target, :card_key, :stage, :exercise_type, :exercise_id,
            :attempt_no, :rating, :answered_at, :content_version, presence: true
  validates :correct, inclusion: { in: [ true, false ] }
  validates :boss_round, inclusion: { in: [ true, false ] }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :rating, numericality: { only_integer: true, in: 1..4 }
  validates :self_rating, numericality: { only_integer: true, in: 1..4 }, allow_nil: true
  validates :trap_axis, inclusion: { in: AXES }, allow_nil: true
  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validates :exercise_id, uniqueness: { scope: %i[arcade_lesson_id attempt_no] }

  scope :for_learner, ->(learner_key) { where(learner_key: learner_key) }
  scope :recent_first, -> { order(answered_at: :desc, id: :desc) }
end

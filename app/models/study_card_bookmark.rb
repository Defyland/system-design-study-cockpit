class StudyCardBookmark < ApplicationRecord
  scope :for_learner, ->(key) { where(learner_key: key) }

  validates :learner_key, :card_key, presence: true
  validates :card_key, uniqueness: { scope: :learner_key }
end

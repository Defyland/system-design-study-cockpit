class Checkpoint < ApplicationRecord
  belongs_to :study_document
  has_many :checkpoint_attempts, dependent: :destroy
  has_many :review_schedules, dependent: :destroy

  validates :source_label, :prompt, :good_answer, presence: true
  validates :position, numericality: { greater_than: 0 }

  def latest_attempt
    checkpoint_attempts.order(answered_at: :desc).first
  end
end

class ReviewSchedule < ApplicationRecord
  STATUSES = {
    pending: "pending",
    completed: "completed",
    skipped: "skipped"
  }.freeze

  enum :status, STATUSES

  belongs_to :study_document
  belongs_to :checkpoint, optional: true

  validates :due_on, :interval_days, :status, presence: true
  validates :interval_days, numericality: { greater_than: 0 }

  scope :due, -> { pending.where(due_on: ..Date.current).order(:due_on, :interval_days) }
end

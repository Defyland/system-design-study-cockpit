class StudyProgress < ApplicationRecord
  STATUSES = {
    not_started: "not_started",
    reading: "reading",
    read: "read",
    drilled: "drilled",
    reviewed: "reviewed",
    mastered: "mastered"
  }.freeze

  enum :status, STATUSES

  belongs_to :study_document

  validates :status, presence: true
  validates :current_block_position, numericality: { greater_than: 0 }

  def mark_seen!(block_position:, status: nil)
    update!(
      current_block_position: block_position,
      last_seen_at: Time.current,
      status: status.presence || next_seen_status
    )
  end

  private

  def next_seen_status
    not_started? ? "reading" : self.status
  end
end

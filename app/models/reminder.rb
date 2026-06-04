class Reminder < ApplicationRecord
  validates :message, :source_kind, :source_slug, presence: true
  validates :priority, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(dismissed_at: nil) }
  scope :visible, -> { active.where("snoozed_until IS NULL OR snoozed_until <= ?", Time.current) }
  scope :ranked, -> { order(priority: :desc, updated_at: :desc) }

  def snooze!(duration = 1.day)
    update!(snoozed_until: duration.from_now)
  end

  def dismiss!
    update!(dismissed_at: Time.current)
  end
end

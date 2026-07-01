class ContentSyncRun < ApplicationRecord
  enum :status, {
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }

  validates :source_mode, :status, :started_at, presence: true

  scope :latest_first, -> { order(started_at: :desc, id: :desc) }

  def self.latest
    latest_first.first
  end

  def self.latest_successful
    succeeded.latest_first.first
  end
end

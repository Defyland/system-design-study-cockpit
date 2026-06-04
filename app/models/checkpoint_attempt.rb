class CheckpointAttempt < ApplicationRecord
  RESULTS = {
    revealed: "revealed",
    correct: "correct",
    hesitant: "hesitant",
    missed: "missed"
  }.freeze

  enum :result, RESULTS

  belongs_to :checkpoint

  validates :result, :answered_at, presence: true

  before_validation :set_answered_at, on: :create

  private

  def set_answered_at
    self.answered_at ||= Time.current
  end
end

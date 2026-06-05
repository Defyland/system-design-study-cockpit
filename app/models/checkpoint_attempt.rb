class CheckpointAttempt < ApplicationRecord
  RESULTS = {
    revealed: "revealed",
    correct: "correct",
    hesitant: "hesitant",
    missed: "missed"
  }.freeze

  CONFIDENCES = {
    low: "low",
    medium: "medium",
    high: "high"
  }.freeze

  enum :result, RESULTS
  enum :confidence, CONFIDENCES

  belongs_to :checkpoint

  validates :result, :answered_at, :prediction_text, :decision_sentence, :confidence, presence: true

  before_validation :set_answered_at, on: :create

  private

  def set_answered_at
    self.answered_at ||= Time.current
  end
end

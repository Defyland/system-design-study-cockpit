class SimulationAttempt < ApplicationRecord
  DECISIONS = {
    safe: "safe",
    risky: "risky",
    rollback: "rollback"
  }.freeze

  CONFIDENCES = {
    low: "low",
    medium: "medium",
    high: "high"
  }.freeze

  enum :decision, DECISIONS
  enum :confidence, CONFIDENCES

  belongs_to :study_document, optional: true

  validates :simulation_slug, :decision, :confidence, presence: true
end

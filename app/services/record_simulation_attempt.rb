class RecordSimulationAttempt
  def self.call(attributes:)
    new(attributes).call
  end

  def initialize(attributes)
    @attributes = attributes
  end

  def call
    SimulationAttempt.transaction do
      engine_result = SimulationEngine.call(
        simulation_slug: attributes.fetch(:simulation_slug),
        input_snapshot: attributes.fetch(:input_snapshot)
      )

      attempt = SimulationAttempt.create!(
        attributes.merge(
          input_snapshot: engine_result.input_snapshot,
          output_snapshot: engine_result.output_snapshot
        )
      )

      MisconceptionTracker.record_simulation_attempt!(attempt)
      create_reminder_for(attempt) if attempt.risky?
      attempt
    end
  end

  private

  attr_reader :attributes

  def create_reminder_for(attempt)
    Reminder.create!(
      source_kind: "simulation_lab",
      source_slug: attempt.simulation_slug,
      message: "Reveja o simulador #{attempt.simulation_slug}: sua decisao ficou arriscada. Explique o rollback em 15 segundos.",
      priority: 2
    )
  end
end

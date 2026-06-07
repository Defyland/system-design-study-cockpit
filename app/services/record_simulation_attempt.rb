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

      attempt = SimulationAttempt.create!(attempt_attributes(engine_result))

      MisconceptionTracker.record_simulation_attempt!(attempt)
      create_reminder_for(attempt) if attempt.risky?
      attempt
    end
  end

  private

  attr_reader :attributes

  def attempt_attributes(engine_result)
    attributes.except(:study_document_id, :output_snapshot).merge(
      study_document: study_document,
      input_snapshot: engine_result.input_snapshot,
      output_snapshot: engine_result.output_snapshot
    )
  end

  def study_document
    StudyDocument.simulation_lab.find_by(slug: attributes.fetch(:simulation_slug))
  end

  def create_reminder_for(attempt)
    Reminder.create!(
      source_kind: "simulation_lab",
      source_slug: attempt.simulation_slug,
      message: "Reveja o simulador #{attempt.simulation_slug}: sua decisao ficou arriscada. Explique o rollback em 15 segundos.",
      priority: 2
    )
  end
end

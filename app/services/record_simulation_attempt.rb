class RecordSimulationAttempt
  def self.call(simulation_slug:, decision:, confidence:, input_snapshot:, feedback: nil)
    new(
      simulation_slug: simulation_slug,
      decision: decision,
      confidence: confidence,
      input_snapshot: input_snapshot,
      feedback: feedback
    ).call
  end

  def initialize(simulation_slug:, decision:, confidence:, input_snapshot:, feedback:)
    @simulation_slug = simulation_slug
    @decision = decision
    @confidence = confidence
    @input_snapshot = input_snapshot
    @feedback = feedback
  end

  def call
    SimulationAttempt.transaction do
      engine_result = SimulationEngine.call(
        simulation_slug: simulation_slug,
        input_snapshot: input_snapshot
      )

      attempt = SimulationAttempt.create!(attempt_attributes(engine_result))

      MisconceptionTracker.record_simulation_attempt!(attempt)
      create_reminder_for(attempt) if SimulationAttemptAssessment.new(attempt).reminder_needed?
      attempt
    end
  end

  private

  attr_reader :simulation_slug, :decision, :confidence, :input_snapshot, :feedback

  def attempt_attributes(engine_result)
    {
      simulation_slug: simulation_slug,
      decision: decision,
      confidence: confidence,
      feedback: feedback,
      study_document: study_document,
      input_snapshot: engine_result.input_snapshot,
      output_snapshot: engine_result.output_snapshot
    }
  end

  def study_document
    StudyDocument.simulation_lab.find_by(slug: simulation_slug)
  end

  def create_reminder_for(attempt)
    reminder = Reminder.find_or_initialize_by(
      source_kind: "simulation_lab",
      source_slug: attempt.simulation_slug
    )
    reminder.assign_attributes(
      message: "Reveja o simulador #{attempt.simulation_slug}: sua decisao ou confianca indicou risco. Explique o rollback em 15 segundos.",
      priority: [ reminder.priority || 0, 2 ].max,
      dismissed_at: nil,
      snoozed_until: nil
    )
    reminder.save!
  end
end

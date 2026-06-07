class MisconceptionTracker
  def self.record_checkpoint_attempt!(attempt)
    new.record_checkpoint_attempt!(attempt)
  end

  def self.record_simulation_attempt!(attempt)
    new.record_simulation_attempt!(attempt)
  end

  def record_checkpoint_attempt!(attempt)
    key = MisconceptionClassifier.for_checkpoint_attempt(attempt)
    return unless key

    attempt.update!(misconception_key: key)
    MisconceptionEvent.create!(
      source_kind: "checkpoint_attempt",
      source_id: attempt.id,
      study_document: attempt.checkpoint.study_document,
      misconception_key: key,
      prompt: attempt.checkpoint.prompt,
      correction: attempt.checkpoint.correction.presence || attempt.checkpoint.good_answer,
      severity: severity_for_checkpoint(attempt)
    )
  end

  def record_simulation_attempt!(attempt)
    key = MisconceptionClassifier.for_simulation_attempt(attempt)
    return unless key

    attempt.update!(misconception_key: key)
    MisconceptionEvent.create!(
      source_kind: "simulation_attempt",
      source_id: attempt.id,
      study_document: attempt.study_document,
      misconception_key: key,
      prompt: "Simulation: #{attempt.simulation_slug}",
      correction: attempt.output_snapshot.fetch("feedback", attempt.feedback.presence || "Explique metrica, mitigacao e rollback."),
      severity: severity_for_simulation(attempt)
    )
  end

  private

  def severity_for_checkpoint(attempt)
    return 3 if attempt.missed?
    return 2 if attempt.hesitant? || attempt.low?

    1
  end

  def severity_for_simulation(attempt)
    SimulationAttemptAssessment.new(attempt).severity
  end
end

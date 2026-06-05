class SimulationAttemptsController < ApplicationController
  def create
    attempt = SimulationAttempt.create!(attempt_attributes)
    MisconceptionTracker.record_simulation_attempt!(attempt)
    create_reminder_for(attempt) if attempt.risky?

    redirect_to simulation_path(attempt.simulation_slug), notice: "Tentativa registrada."
  end

  private

  def attempt_attributes
    permitted = params.require(:simulation_attempt).permit(
      :study_document_id,
      :simulation_slug,
      :decision,
      :confidence,
      :feedback,
      :input_snapshot,
      :output_snapshot
    )

    permitted[:input_snapshot] = parse_snapshot(permitted[:input_snapshot])
    permitted[:output_snapshot] = parse_snapshot(permitted[:output_snapshot])
    permitted
  end

  def parse_snapshot(value)
    return value if value.is_a?(Hash)

    JSON.parse(value.presence || "{}")
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

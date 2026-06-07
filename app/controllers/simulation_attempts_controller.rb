class SimulationAttemptsController < ApplicationController
  def create
    attempt = RecordSimulationAttempt.call(attributes: attempt_attributes)

    redirect_to simulation_path(attempt.simulation_slug), notice: "Tentativa registrada."
  end

  private

  def attempt_attributes
    permitted = params.require(:simulation_attempt).permit(
      :simulation_slug,
      :decision,
      :confidence,
      :feedback,
      :input_snapshot
    )

    permitted[:input_snapshot] = parse_snapshot(permitted[:input_snapshot])
    permitted.to_h.symbolize_keys
  end

  def parse_snapshot(value)
    return value if value.is_a?(Hash)

    JSON.parse(value.presence || "{}")
  end
end

class SimulationsController < ApplicationController
  def index
    @simulations = SimulationCatalog.all
    @documents = StudyDocument.simulation_lab.index_by(&:slug)
    @attempt_counts = SimulationAttempt.group(:simulation_slug).count
  end

  def show
    @simulation = simulation
    @document = StudyDocument.simulation_lab.find_by(slug: @simulation.slug)
    @recent_attempts = SimulationAttempt
      .where(simulation_slug: @simulation.slug)
      .order(created_at: :desc)
      .limit(5)
  end

  def evaluate
    result = SimulationEngine.call(
      simulation_slug: simulation.slug,
      input_snapshot: input_snapshot
    )

    render json: {
      inputSnapshot: result.input_snapshot,
      outputSnapshot: result.output_snapshot
    }
  end

  private

  def simulation
    @simulation ||= SimulationCatalog.find!(params.fetch(:slug))
  end

  def input_snapshot
    params.fetch(:input_snapshot, ActionController::Parameters.new)
      .permit(*simulation.controls.map(&:key))
      .to_h
  end
end

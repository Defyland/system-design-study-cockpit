class LibraryController < ApplicationController
  KIND_LABELS = {
    "foundation" => "Foundations",
    "component_card" => "Componentes",
    "simulation_lab" => "Simulation Labs",
    "ai_system" => "Sistemas de IA",
    "real_world_case" => "Casos reais",
    "decision_contrast" => "Contrastes"
  }.freeze

  def index
    @kind = params.fetch(:kind)
    @title = KIND_LABELS.fetch(@kind)
    @documents = StudyDocument.where(kind: @kind).in_study_order
  end

  def show
    @kind = params.fetch(:kind)
    @title = KIND_LABELS.fetch(@kind)
    @document = StudyDocument.where(kind: @kind).find_by!(slug: params.fetch(:slug))
    @blocks = @document.study_blocks
  end
end

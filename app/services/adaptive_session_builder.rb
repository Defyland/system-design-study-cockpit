class AdaptiveSessionBuilder
  Item = Struct.new(:kind, :title, :prompt, :reason, :path, keyword_init: true)
  LIBRARY_KINDS = %w[
    foundation
    component_card
    simulation_lab
    ai_system
    real_world_case
    decision_contrast
  ].freeze

  include Rails.application.routes.url_helpers

  def initialize(limit: 7)
    @limit = limit
  end

  def call
    candidates = []
    candidates.concat(due_review_items)
    candidates.concat(misconception_items)
    candidates.concat(low_confidence_checkpoint_items)
    candidates.concat(risky_simulation_items)
    candidates.concat(decision_contrast_items)

    candidates.uniq { |item| [ item.kind, item.path, item.prompt ] }.first(@limit)
  end

  private

  def due_review_items
    ReviewSchedule.due.includes(:study_document, :checkpoint).limit(3).map do |schedule|
      document = schedule.study_document
      Item.new(
        kind: "review",
        title: document.title,
        prompt: schedule.checkpoint&.prompt || "Explique o documento sem abrir a resposta.",
        reason: "Review vencido de #{schedule.interval_days}d",
        path: path_for_document(document)
      )
    end
  end

  def misconception_items
    MisconceptionEvent.severe_first.includes(:study_document).limit(3).map do |event|
      Item.new(
        kind: "misconception",
        title: event.misconception_key.humanize,
        prompt: event.prompt.presence || "Explique o erro de julgamento e a correcao.",
        reason: "Misconception recorrente ou severa",
        path: path_for_event(event)
      )
    end
  end

  def low_confidence_checkpoint_items
    CheckpointAttempt
      .where(confidence: %w[low medium])
      .includes(checkpoint: :study_document)
      .order(answered_at: :desc)
      .limit(3)
      .map do |attempt|
        document = attempt.checkpoint.study_document
        Item.new(
          kind: "confidence",
          title: document.title,
          prompt: attempt.checkpoint.prompt,
          reason: "Confidence #{attempt.confidence}",
          path: path_for_document(document)
        )
      end
  end

  def risky_simulation_items
    SimulationAttempt
      .where("decision != ? OR confidence IN (?)", "safe", %w[low medium])
      .order(created_at: :desc)
      .limit(3)
      .map do |attempt|
        Item.new(
          kind: "simulation",
          title: attempt.simulation_slug.humanize,
          prompt: "Reexecute a simulacao e diga a primeira metrica, mitigacao e rollback.",
          reason: "Simulacao com risco ou baixa confianca",
          path: simulation_path(attempt.simulation_slug)
        )
      end
  end

  def decision_contrast_items
    StudyDocument.decision_contrast.in_study_order.limit(2).map do |document|
      Item.new(
        kind: "contrast",
        title: document.title,
        prompt: "Diga a diferenca em 15 segundos antes de abrir o contraste.",
        reason: "Interleaving para nao confundir decisoes parecidas",
        path: library_document_path(kind: "decision_contrast", slug: document.slug)
      )
    end
  end

  def path_for_event(event)
    return simulation_path(simulation_slug_for(event)) if event.source_kind == "simulation_attempt"

    path_for_document(event.study_document)
  end

  def simulation_slug_for(event)
    SimulationAttempt.find_by(id: event.source_id)&.simulation_slug || event.study_document&.slug
  end

  def path_for_document(document)
    return root_path unless document
    return chapter_path(document.slug) if document.chapter?
    return library_document_path(kind: document.kind, slug: document.slug) if library_kind?(document.kind)

    drills_path
  end

  def library_kind?(kind)
    LIBRARY_KINDS.include?(kind)
  end
end

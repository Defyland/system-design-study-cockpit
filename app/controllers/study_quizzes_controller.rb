class StudyQuizzesController < ApplicationController
  include ArcadeLearnerIdentity
  layout "study_cards"
  before_action :load_catalog

  def index
    @topics = StudyCardCatalog.new.topics.select { |key, _label| @catalog.cards.any? { |card| StudyCardCatalog.in_topic?(card, key) } }
    @rounds = StudyQuizRound.for_learner(learner_key).order(updated_at: :desc).reject(&:finished?)
    @answered_count = StudyQuizRound.answered_keys(learner_key).size
  end

  def create
    topic = params[:topic].to_s
    return head :unprocessable_entity unless topic == "all" || StudyCardCatalog.new.topics.key?(topic)

    mode = params[:mode] == "errors" ? "errors" : "new"
    source_ids = Array(params[:source_ids]).reject(&:blank?).map(&:to_i).uniq.sort
    return head :unprocessable_entity if source_ids.any? && StudyDocument.where(id: source_ids).count != source_ids.size

    existing = StudyQuizRound.for_learner(learner_key).where(topic: topic, mode: mode).order(id: :desc).detect { |round| !round.finished? && round.source_ids == source_ids }
    return redirect_to study_quiz_path(existing) if existing

    keys = @catalog.cards.select { |card| StudyCardCatalog.in_topic?(card, topic) && (source_ids.empty? || (@catalog.source_document_ids(card) & source_ids).any?) }.map { |card| card[:id] }
    keys &= mode == "errors" ? StudyQuizRound.error_keys(learner_key) : keys - StudyQuizRound.answered_keys(learner_key)
    if keys.empty?
      redirect_to study_quizzes_path, notice: mode == "errors" ? "Nenhum erro para revisar nesta trilha." : "Nenhuma pergunta inédita elegível nesta trilha."
      return
    end
    round = StudyQuizRound.create!(learner_key: learner_key, topic: topic, mode: mode, card_keys: keys.take(50), source_ids: source_ids)
    redirect_to study_quiz_path(round)
  end

  def show
    @round = StudyQuizRound.for_learner(learner_key).find(params[:id])
    @card = @catalog.find(@round.current_key) unless @round.finished?
    @choices = @catalog.choices(@card) if @card
    @response = @round.responses[@round.current_key] if @card
    @source_documents = StudyDocument.where(id: @catalog.source_document_ids(@card)) if @card
  end

  def update
    round = StudyQuizRound.for_learner(learner_key).find(params[:id])
    round.with_lock do
      if !round.finished? && params[:position].to_s == round.position.to_s && params[:card_key] == round.current_key
        card = @catalog.find(round.current_key)
        if card
          response = round.responses[round.current_key]
          if params[:direction] == "answer" && response.nil?
            choice = @catalog.choices(card).find { |item| item["id"] == params[:choice_id] }
            if choice
              round.update!(responses: round.responses.merge(round.current_key => { "choice_id" => choice.fetch("id"), "correct" => choice.fetch("correct") }))
            end
          elsif params[:direction] == "next" && response
            round.update!(position: round.position + 1)
          end
        end
      end
    end
    redirect_to study_quiz_path(round), status: :see_other
  end

  private

  def load_catalog
    @catalog = StudyQuizCatalog.new
  end
end

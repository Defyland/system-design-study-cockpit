class StudyCardsController < ApplicationController
  include ArcadeLearnerIdentity
  layout "study_cards"
  before_action :load_catalog, except: %i[source update]

  def index
    @completed = StudyCardRound.completed_keys(learner_key)
    @rounds = StudyCardRound.for_learner(learner_key).order(updated_at: :desc).reject(&:finished?)
  end

  def create
    topic = params[:topic].to_s
    return head :unprocessable_entity unless @topics.key?(topic)

    replay = params[:mode] == "replay"
    completed = StudyCardRound.completed_keys(learner_key)
    keys = @catalog.select { |card| StudyCardCatalog.in_topic?(card, topic) }
      .map { |card| card.fetch(:id) }.select { |key| replay == completed.include?(key) }.take(50)
    if keys.empty?
      redirect_to study_cards_path, notice: replay ? "Nenhum card feito neste assunto." : "Você concluiu os inéditos deste assunto. Repita somente quando quiser."
      return
    end
    existing = StudyCardRound.for_learner(learner_key).where(topic: topic, replay: replay).order(id: :desc).detect { |round| !round.finished? }
    round = existing || StudyCardRound.create!(learner_key: learner_key, topic: topic, replay: replay, card_keys: keys)
    redirect_to study_card_path(round)
  end

  def show
    @round = StudyCardRound.for_learner(learner_key).find(params[:id])
    @round.remove_completed_cards!
    @card = @catalog.find { |card| card.fetch(:id) == @round.card_keys[@round.position] } unless @round.finished?
  end

  def source
    @document = StudyDocument.find(params[:id])
  end

  def update
    round = StudyCardRound.for_learner(learner_key).find(params[:id])
    round.with_lock do
      # A stale page or a duplicated swipe must never consume the next card.
      if params[:position].to_s == round.position.to_s
        if params[:direction] == "next" && !round.finished? && params[:card_key] == round.card_keys[round.position]
          round.update!(position: round.position + 1)
        elsif params[:direction] == "undo" && round.position.positive?
          round.update!(position: round.position - 1)
        end
      end
    end
    redirect_to study_card_path(round), status: :see_other
  end

  private

  def load_catalog
    catalog = StudyCardCatalog.new
    @catalog = catalog.cards
    @topics = catalog.topics
  end
end

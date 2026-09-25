class StudyWorkspaceController < ApplicationController
  include ArcadeLearnerIdentity
  layout "study_cards"

  def guide
    @topic = StudyCardCatalog.new.topics.key?(params[:topic].to_s) ? params[:topic].to_s : "all"
    @source_ids = selected_source_ids
    scope = @source_ids.any? ? StudyDocument.where(id: @source_ids) : StudyDocument.all
    if @source_ids.empty? && @topic != "all"
      matching_ids = StudyDocumentCards.new.cards.select { |card| StudyCardCatalog.in_topic?(card, @topic) }.map { |card| card[:document_id] }
      scope = scope.where(id: matching_ids)
    end
    @documents = scope.ordered
    @document = params[:document_id].present? ? @documents.find_by(id: params[:document_id]) : @documents.first
    @missing_source = params[:document_id].present? && !@document
    return unless @document

    @sections = StudyDocumentCards.new(documents: [@document]).cards
    @selected = params[:section].present? ? @sections.find { |section| section[:id] == params[:section] } : @sections.first
    @missing_source ||= params[:section].present? && !@selected
    @groups = {
      "Entenda" => @sections.reject { |section| practice?(section) || comparison?(section) },
      "Compare" => @sections.select { |section| comparison?(section) },
      "Pratique" => @sections.select { |section| practice?(section) }
    }
    selected_group = @groups.find { |_name, sections| sections.include?(@selected) }&.first
    @active_tab = @groups.key?(params[:tab]) ? params[:tab] : (selected_group || @groups.find { |_name, sections| sections.any? }&.first || "Entenda")
    @selected = params[:section].present? ? @groups[@active_tab].find { |section| section == @selected } : @groups[@active_tab].first
  end

  def map
    @topics = StudyCardCatalog.new.topics
    @selected_topic = @topics.key?(params[:topic].to_s) ? params[:topic].to_s : "all"
    cards_by_document = StudyDocumentCards.new.cards.group_by { |card| card[:document_id] }
    @source_ids = selected_source_ids
    scope = @source_ids.any? ? StudyDocument.where(id: @source_ids).ordered : StudyDocument.ordered
    @documents = scope.to_a.filter_map do |document|
      sections = cards_by_document.fetch(document.id, []).select { |card| StudyCardCatalog.in_topic?(card, @selected_topic) }
      [document, sections] if sections.any?
    end
    @selected_document = @documents.map(&:first).find { |document| document.id.to_s == params[:document_id].to_s } if params[:document_id].present?
    @selected_section = StudyDocumentCards.new(documents: [@selected_document]).cards.find { |section| section[:id] == params[:section] } if @selected_document && params[:section].present?
  end

  def configure
    @topics = StudyCardCatalog.new.topics
    @topic = @topics.key?(params[:topic].to_s) ? params[:topic].to_s : "all"
    @source_ids = selected_source_ids
    @whole_topic = params[:scope] == "all" && @source_ids.empty?
    @documents = StudyDocument.where(id: @source_ids).ordered
    if @whole_topic || (@source_ids.any? && @documents.size == @source_ids.size)
      cards = StudyCardCatalog.new.cards.select { |card| StudyCardCatalog.in_topic?(card, @topic) && (@whole_topic || @source_ids.include?(card[:document_id])) }
      completed = StudyCardRound.completed_keys(learner_key)
      @new_count = cards.count { |card| !completed.include?(card[:id]) }
      @review_count = cards.count { |card| completed.include?(card[:id]) }
      quiz = StudyQuizCatalog.new
      answered = StudyQuizRound.answered_keys(learner_key)
      @quiz_count = quiz.cards.count { |card| StudyCardCatalog.in_topic?(card, @topic) && (@whole_topic || (quiz.source_document_ids(card) & @source_ids).any?) && !answered.include?(card[:id]) }
      return
    end

    redirect_to study_cards_path(topic: @topic), notice: "Selecione pelo menos uma fonte existente para escolher o formato."
  end

  def start
    topic = params[:topic].to_s
    return head :unprocessable_entity unless StudyCardCatalog.new.topics.key?(topic)

    source_ids = selected_source_ids
    whole_topic = params[:scope] == "all" && source_ids.empty?
    return head :unprocessable_entity unless whole_topic || (source_ids.any? && StudyDocument.where(id: source_ids).count == source_ids.size)

    case params[:format]
    when "guide" then redirect_to study_guide_path(topic: topic, document_id: source_ids.first, source_ids: source_ids)
    when "map" then redirect_to study_map_path(topic: topic, source_ids: source_ids)
    when "quiz"
      existing = StudyQuizRound.for_learner(learner_key).where(topic: topic, mode: "new").order(id: :desc).detect { |round| !round.finished? && round.source_ids == source_ids }
      return redirect_to study_quiz_path(existing) if existing

      catalog = StudyQuizCatalog.new
      answered = StudyQuizRound.answered_keys(learner_key)
      keys = catalog.cards.select { |card| StudyCardCatalog.in_topic?(card, topic) && (whole_topic || (catalog.source_document_ids(card) & source_ids).any?) && !answered.include?(card[:id]) }.map { |card| card[:id] }.take(50)
      return redirect_to study_configure_path(topic: topic, source_ids: source_ids, scope: ("all" if whole_topic)), notice: "Este escopo não tem perguntas inéditas elegíveis no Arcade." if keys.empty?

      round = StudyQuizRound.create!(learner_key: learner_key, topic: topic, card_keys: keys, source_ids: source_ids)
      redirect_to study_quiz_path(round)
    when "cards"
      replay = params[:mode] == "replay"
      completed = StudyCardRound.completed_keys(learner_key)
      keys = StudyCardCatalog.new.cards.select { |card| StudyCardCatalog.in_topic?(card, topic) && (whole_topic || source_ids.include?(card[:document_id])) && (replay == completed.include?(card[:id])) }.map { |card| card[:id] }.take(50)
      return redirect_to study_configure_path(topic: topic, source_ids: source_ids, scope: ("all" if whole_topic)), notice: replay ? "Nenhum card lido neste escopo." : "Nenhum card inédito neste escopo. Revisão é opcional." if keys.empty?

      existing = StudyCardRound.for_learner(learner_key).where(topic: topic, replay: replay).order(id: :desc).detect { |round| !round.finished? && round.source_ids == source_ids }
      round = existing || StudyCardRound.create!(learner_key: learner_key, topic: topic, replay: replay, card_keys: keys, source_ids: source_ids)
      redirect_to study_card_path(round)
    else head :unprocessable_entity
    end
  end

  def review
    catalog = StudyCardCatalog.new.cards.index_by { |card| card[:id] }
    @saved = StudyCardBookmark.for_learner(learner_key).order(updated_at: :desc).pluck(:card_key).filter_map { |key| catalog[key] }
    @completed = StudyCardRound.completed_keys(learner_key).filter_map { |key| catalog[key] }
    quiz = StudyQuizCatalog.new(cards: catalog.values)
    @errors = StudyQuizRound.error_keys(learner_key).filter_map { |key| quiz.find(key) }
    @kind = %w[saved errors completed].include?(params[:kind]) ? params[:kind] : "saved"
    @topics = StudyCardCatalog.new.topics
    @topic = @topics.key?(params[:topic].to_s) ? params[:topic].to_s : "all"
    @items = { "saved" => @saved, "errors" => @errors, "completed" => @completed }.fetch(@kind)
      .select { |card| StudyCardCatalog.in_topic?(card, @topic) }
  end

  def start_review
    kind = params[:kind].to_s
    if kind == "errors"
      keys = StudyQuizRound.error_keys(learner_key) & StudyQuizCatalog.new.cards.map { |card| card[:id] }
      keys &= Array(params[:card_keys]) if params.key?(:card_keys)
      return redirect_to study_review_path, notice: "Nenhum erro do quiz para revisar." if keys.empty?

      round = StudyQuizRound.create!(learner_key: learner_key, topic: "all", mode: "errors", card_keys: keys.take(50))
      return redirect_to study_quiz_path(round)
    end

    keys = case kind
    when "saved" then StudyCardBookmark.for_learner(learner_key).order(updated_at: :desc).pluck(:card_key)
    when "completed" then StudyCardRound.completed_keys(learner_key)
    else return head :unprocessable_entity
    end
    keys &= Array(params[:card_keys]) if params.key?(:card_keys)
    keys &= StudyCardCatalog.new.cards.map { |card| card[:id] }
    return redirect_to study_review_path, notice: "Nenhum card nesta lista ainda." if keys.empty?

    round = StudyCardRound.create!(learner_key: learner_key, topic: kind, replay: true, card_keys: keys.take(50))
    redirect_to study_card_path(round)
  end

  private

  def selected_source_ids
    Array(params[:source_ids]).reject(&:blank?).map(&:to_i).uniq.sort
  end

  def practice?(section)
    section[:answer_markdown].match?(/\*\*Q:|\bexerc[ií]cio\b|\bperguntas?\b/i)
  end

  def comparison?(section)
    section[:answer_markdown].match?(/\bcompar(?:e|ar|ação)|\bversus\b|\btrade.?off\b/i)
  end
end

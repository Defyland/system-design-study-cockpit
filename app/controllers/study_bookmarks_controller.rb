class StudyBookmarksController < ApplicationController
  include ArcadeLearnerIdentity

  def create
    key = params[:card_key].to_s
    return head :unprocessable_entity unless StudyCardCatalog.new.cards.any? { |card| card[:id] == key }

    StudyCardBookmark.create_or_find_by!(learner_key: learner_key, card_key: key)
    redirect_back fallback_location: study_review_path, status: :see_other
  end

  def destroy
    StudyCardBookmark.for_learner(learner_key).where(card_key: params[:card_key]).delete_all
    redirect_back fallback_location: study_review_path, status: :see_other
  end
end

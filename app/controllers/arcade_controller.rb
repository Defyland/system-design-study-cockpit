class ArcadeController < ApplicationController
  include ArcadeLearnerIdentity

  layout "arcade"

  def show
    @progress = ArcadeProgressDashboard.new(learner_key: learner_key).call
    @resume_lesson = ArcadeLesson.for_learner(learner_key).active
      .where("exercises_total > 0").order(updated_at: :desc, id: :desc).first

    respond_to do |format|
      format.html
      format.json { render json: @progress }
    end
  end
end

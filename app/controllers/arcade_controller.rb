class ArcadeController < ApplicationController
  include ArcadeLearnerIdentity

  layout "arcade"

  def show
    @progress = ArcadeProgressDashboard.new(learner_key: learner_key).call

    respond_to do |format|
      format.html
      format.json { render json: @progress }
    end
  end
end

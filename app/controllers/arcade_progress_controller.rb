class ArcadeProgressController < ApplicationController
  include ArcadeLearnerIdentity

  def show
    render json: ArcadeProgressDashboard.new(learner_key: learner_key).call
  end
end

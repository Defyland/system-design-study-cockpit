module ArcadeLearnerIdentity
  extend ActiveSupport::Concern

  private

  def learner_key
    request.get_header("REMOTE_USER").presence || ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end
end

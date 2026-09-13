class ArcadeController < ApplicationController
  include ArcadeLearnerIdentity

  layout "arcade"

  WARMUP_CUES = { "frontend" => "performance", "backend" => "reliability", "fullstack" => "ownership", "smarttv" => "playback" }.freeze

  def warmup
    @roles = EnglishArcadeResumeInterviewProfile.role_metadata
    @role = params[:interview_role].presence || "fullstack"
    return render plain: "Unknown interview role", status: :unprocessable_entity unless @roles.key?(@role)

    card = ArcadeContent.new.items_for("interview", interview_role: @role).first
    @warmup_payload = {
      "role_label" => @roles.fetch(@role).fetch(:label),
      "cue" => WARMUP_CUES.fetch(@role),
      "prompt" => card.fetch("prompt"),
      "follow_up" => card.fetch("follow_up").fetch("prompt")
    }
  end

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

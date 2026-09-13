class ArcadeLessonsController < ApplicationController
  include ArcadeLearnerIdentity

  layout "arcade"

  before_action :load_lesson, only: %i[show finish]

  def create
    payload = lesson_params
    mode = payload[:target_mode].to_s.presence || "mixed"
    target = payload[:target].to_s.presence
    card_key = payload[:card_key].to_s.presence
    interview_role = payload[:interview_role].to_s.presence
    unless ArcadeLesson::TARGET_MODES.include?(mode) && valid_target?(mode, target, card_key, interview_role)
      return render_invalid_target
    end

    lesson = ArcadeLessonComposer.new(learner_key: learner_key).call(
      target_mode: mode,
      target: target,
      card_key: card_key,
      interview_role: interview_role,
      size: payload[:size].presence || ArcadeLessonComposer::SIZE,
      new_cards: payload[:new_cards].presence || ArcadeLessonComposer::MAX_NEW,
      seed: payload[:seed],
      boss_only: payload[:boss_only].to_s == "true"
    )
    if request.format.html?
      redirect_to arcade_lesson_path(lesson), status: :see_other
    else
      render_lesson(lesson, status: :created)
    end
  rescue ArgumentError => error
    return render_invalid_target if error.message == "invalid_target"
    return render_error("empty_lesson", :unprocessable_entity) if error.message == "empty_lesson"
    render_error("stale_content", :unprocessable_entity)
  end

  def show
    render_lesson(@lesson, status: :ok)
  rescue ArcadeLessonComposer::StaleContent, ArgumentError
    render_error("stale_content", :unprocessable_entity)
  end

  def finish
    result = ArcadeLessonRecorder.new(learner_key: learner_key).finish(
      lesson: @lesson,
      duration_ms: params[:duration_ms]
    )
    respond_to do |format|
      format.html { redirect_to arena_path, notice: "Arena lesson saved." }
      format.json { render json: result, status: :ok }
    end
  rescue ArcadeLessonRecorder::Finished
    render_error("lesson_finished", :conflict)
  rescue ArcadeLessonRecorder::InvalidResult => error
    render_error(error.code, :unprocessable_entity)
  end

  private

  def load_lesson
    @lesson = ArcadeLesson.find_by(id: params[:id], learner_key: learner_key)
    return if @lesson

    respond_to do |format|
      format.html { render plain: "Not found", status: :not_found }
      format.json { render json: { error: "not_found" }, status: :not_found }
    end
  end

  def lesson_params
    params.fetch(:lesson, {}).permit(:target_mode, :target, :card_key, :interview_role, :size, :new_cards, :seed, :boss_only)
  end

  def valid_target?(mode, target, card_key, interview_role)
    return true if mode == "mixed"
    if mode == "interview"
      return true if interview_role.blank?

      return EnglishArcadeResumeInterviewProfile.interview_roles.include?(interview_role.to_s.downcase.strip)
    end
    return false if target.blank?

    normalized = ArcadeContent.new.normalize_target(target)
    return false unless EnglishArcade::Schema::TARGETS.include?(normalized)
    return true unless mode == "card"

    card_key.present? && ArcadeContent.new.item_for(target: normalized, card_key: card_key).present?
  end

  def render_lesson(lesson, status:)
    composer = ArcadeLessonComposer.new(learner_key: learner_key)
    resume_position = lesson.summary.to_h.fetch("next_position", 0).to_i
    exercises = composer.exercises_for(lesson, current_position: resume_position).each_with_index.map do |exercise, index|
      index == resume_position ? exercise : exercise.slice("exercise_id", "card_key", "target", "stage", "type", "position", "attempt_no", "reason", "boss")
    end
    payload = {
      "id" => lesson.id,
      "target_mode" => lesson.target_mode,
      "target" => lesson.target,
      "interview_role" => composer.content.item_by_key(lesson.plan.first.fetch("card_key"))&.fetch("interview_role", nil),
      "targets" => lesson.targets,
      "status" => lesson.status,
      "seed" => lesson.seed,
      "resume_position" => resume_position,
      "exercises" => exercises,
      "totals" => {
        "total" => lesson.exercises_total,
        "done" => lesson.exercises_done,
        "new_cards" => lesson.new_cards_count,
        "review" => lesson.review_count,
        "boss" => lesson.boss_total
      },
      "urls" => {
        "result" => arcade_lesson_results_path(lesson_id: lesson.id),
        "finish" => finish_arcade_lesson_path(lesson)
      }
    }
    respond_to do |format|
      format.html do
        @lesson_payload = payload
        @companion_base_url = companion_base_url
        render :show, status: status
      end
      format.json { render json: { lesson: payload }, status: status }
    end
  end

  def render_invalid_target
    render_error("invalid_target", :unprocessable_entity)
  end

  def companion_base_url
    port = Integer(ENV.fetch("ENGLISH_ARCADE_VOICE_COMPANION_PORT", "43129"), 10)
    port = 43_129 unless port.between?(1, 65_535)
    "http://127.0.0.1:#{port}"
  rescue ArgumentError
    "http://127.0.0.1:43129"
  end

  def render_error(code, status)
    respond_to do |format|
      format.html do
        if code.to_s == "stale_content"
          render :stale_content, status: status
        else
          render plain: code.to_s, status: status
        end
      end
      format.json { render json: { error: code.to_s }, status: status }
    end
  end
end

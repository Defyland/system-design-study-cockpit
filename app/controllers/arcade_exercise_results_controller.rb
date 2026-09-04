class ArcadeExerciseResultsController < ApplicationController
  include ArcadeLearnerIdentity

  before_action :load_lesson

  def create
    result = ArcadeLessonRecorder.new(learner_key: learner_key).call(
      lesson: @lesson,
      result: result_params.to_h
    )
    idempotent = result.delete("_idempotent") == true
    render json: result, status: idempotent ? :ok : :created
  rescue ArcadeLessonRecorder::Finished
    render json: { error: "lesson_finished" }, status: :conflict
  rescue ArcadeLessonRecorder::StaleContent
    render json: { error: "stale_content" }, status: :unprocessable_entity
  rescue ArcadeLessonRecorder::Tampered, ArcadeLessonRecorder::InvalidResult => error
    render json: { error: error.respond_to?(:code) ? error.code : "invalid_result" }, status: :unprocessable_entity
  end

  private

  def load_lesson
    @lesson = ArcadeLesson.find_by(id: params[:lesson_id], learner_key: learner_key)
    return if @lesson

    render json: { error: "not_found" }, status: :not_found
  end

  def result_params
    raw = params.fetch(:result, {})
    permitted = raw.permit(:exercise_id, :response_text, :response_ms, :self_rating)
    response = raw[:response]
    normalized = case response
    when ActionController::Parameters, Hash
      source = response.respond_to?(:to_unsafe_h) ? response.to_unsafe_h : response
      source.first(32).to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.byteslice(0, 512).to_s }
    when Array then response.first(64).map { |entry| entry.to_s.byteslice(0, 512).to_s }
    else response.to_s.byteslice(0, 512).to_s
    end
    permitted.to_h.merge("response" => normalized)
  end
end

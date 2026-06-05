class CheckpointAttemptsController < ApplicationController
  def create
    checkpoint = Checkpoint.find(params[:checkpoint_id])
    attempt = checkpoint.checkpoint_attempts.create!(attempt_params)
    ReviewScheduler.schedule!(attempt)
    MisconceptionTracker.record_checkpoint_attempt!(attempt)

    redirect_back fallback_location: chapter_path(checkpoint.study_document.slug), notice: "Checkpoint registrado."
  end

  private

  def attempt_params
    params.expect(checkpoint_attempt: [
      :result,
      :prediction_text,
      :decision_sentence,
      :confidence
    ])
  end
end

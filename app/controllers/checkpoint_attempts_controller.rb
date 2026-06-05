class CheckpointAttemptsController < ApplicationController
  def create
    checkpoint = Checkpoint.find(params[:checkpoint_id])
    RecordCheckpointAttempt.call(checkpoint: checkpoint, attributes: attempt_params)

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

class CheckpointAttemptsController < ApplicationController
  def create
    checkpoint = Checkpoint.find(params[:checkpoint_id])
    attempt = checkpoint.checkpoint_attempts.create!(result: attempt_params.fetch(:result))
    ReviewScheduler.schedule!(attempt)

    redirect_back fallback_location: chapter_path(checkpoint.study_document.slug)
  end

  private

  def attempt_params
    params.expect(checkpoint_attempt: [ :result ])
  end
end

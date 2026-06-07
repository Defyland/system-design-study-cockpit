class StudyProgressesController < ApplicationController
  def update
    progress = StudyProgress.find(params[:id])
    progress.mark_seen!(
      block_position: progress_params.fetch(:current_block_position).to_i,
      status: progress_params[:status]
    )

    redirect_back fallback_location: root_path
  end

  private

  def progress_params
    params.expect(study_progress: [ :current_block_position, :status ])
  end
end

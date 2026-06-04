class StudyProgressesController < ApplicationController
  def update
    document = StudyDocument.find(params[:study_document_id])
    progress = document.progress
    progress.mark_seen!(block_position: progress_params.fetch(:current_block_position).to_i)
    progress.update!(status: progress_params.fetch(:status)) if progress_params[:status].present?

    redirect_back fallback_location: root_path
  end

  private

  def progress_params
    params.expect(study_progress: [ :current_block_position, :status ])
  end
end

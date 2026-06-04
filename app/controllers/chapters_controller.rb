class ChaptersController < ApplicationController
  def index
    @chapters = StudyDocument.chapter.in_study_order.includes(:study_progress)
  end

  def show
    @chapter = StudyDocument.chapter.find_by!(slug: params[:slug])
    @progress = @chapter.progress
    @blocks = @chapter.study_blocks
    @checkpoint_slots = checkpoint_slots(@chapter)
  end

  private

  def checkpoint_slots(chapter)
    blocks_count = [ chapter.study_blocks.size, 1 ].max

    chapter.checkpoints.each_with_index.to_h do |checkpoint, index|
      slot = [ (index + 1) * 3, blocks_count ].min
      [ slot, checkpoint ]
    end
  end
end

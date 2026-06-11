class LibraryController < ApplicationController
  KIND_LABELS = ContentKind.library_labels.freeze

  def index
    @kind = params.fetch(:kind)
    @title = KIND_LABELS.fetch(@kind)
    @documents = StudyDocument.where(kind: @kind).in_study_order
  end

  def show
    @kind = params.fetch(:kind)
    @title = KIND_LABELS.fetch(@kind)
    @document = StudyDocument.where(kind: @kind).find_by!(slug: params.fetch(:slug))
    @blocks = @document.study_blocks
    @side_track = StudyDocument.side_track_overview.find_by(slug: @document.side_track_id) if @document.side_track_id.present?
    @linked_review_card = StudyDocument.side_track_review_card.find_by(source_path: @document.metadata["review_card_path"]) if @document.metadata["review_card_path"].present?
    @linked_chapter = StudyDocument.side_track_chapter.find_by(source_path: @document.metadata["chapter_path"]) if @document.metadata["chapter_path"].present?
  end
end

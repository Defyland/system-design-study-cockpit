class SideTracksController < ApplicationController
  def index
    @side_tracks = StudyDocument.side_track_overview.in_study_order.includes(:study_mission)
    @chapter_counts = StudyDocument.side_track_chapter.group("metadata ->> 'side_track_id'").count
    @record_counts = LearningRecord.joins(:study_document).group("study_documents.slug").count
  end

  def show
    @side_track = StudyDocument.side_track_overview.find_by!(slug: params[:slug])
    @blocks = @side_track.study_blocks
    @chapters = StudyDocument.side_track_chapter.for_side_track(@side_track.slug).in_study_order.includes(:study_progress)
    @review_cards = StudyDocument.side_track_review_card.for_side_track(@side_track.slug).in_study_order
    @review_cards_by_path = @review_cards.index_by(&:source_path)
    @source_map = StudyDocument.side_track_reference.find_by(source_path: @side_track.metadata["source_map_path"])
    @review_guide = StudyDocument.side_track_reference.find_by(source_path: @side_track.metadata["reviews_readme_path"])
    @mission = @side_track.study_mission || @side_track.build_study_mission
    @learning_records = @side_track.learning_records.includes(:related_document).order(created_at: :desc)
    @learning_record = @side_track.learning_records.build
    @related_document_options = related_document_options
  end

  private

  def related_document_options
    chapter_options = @chapters.map do |document|
      [ "Chapter #{document.position.to_s.rjust(2, "0")} · #{document.title}", document.id ]
    end
    review_options = @review_cards.map do |document|
      [ "Review · #{document.title}", document.id ]
    end

    chapter_options + review_options
  end
end

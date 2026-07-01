class LibraryController < ApplicationController
  KIND_LABELS = ContentKind.library_labels.freeze

  def index
    @kind = params.fetch(:kind)
    @title = KIND_LABELS.fetch(@kind)
    @query = params[:q].to_s.strip
    @documents = if @query.present?
      StudySearch.new(q: @query, kind: @kind).results
    else
      StudyDocument.where(kind: @kind).in_study_order
    end
  end

  def show
    @kind = params.fetch(:kind)
    @title = KIND_LABELS.fetch(@kind)
    @document = StudyDocument.where(kind: @kind).find_by!(slug: params.fetch(:slug))
    @blocks = display_blocks
    @side_track = StudyDocument.side_track_overview.find_by(slug: @document.side_track_id) if @document.side_track_id.present?
    @linked_review_card = StudyDocument.side_track_review_card.find_by(source_path: @document.metadata["review_card_path"]) if @document.metadata["review_card_path"].present?
    @linked_chapter = StudyDocument.side_track_chapter.find_by(source_path: @document.metadata["chapter_path"]) if @document.metadata["chapter_path"].present?
    @story_bank_layout = build_story_bank_layout
  end

  private

  def build_story_bank_layout
    return unless @document.interview_story_bank?

    layout = InterviewStoryBankLayout.new(document: @document)
    layout if layout.available?
  end

  def display_blocks
    blocks = @document.study_blocks.to_a
    return blocks unless duplicate_title_heading?(blocks.first)

    blocks.drop(1)
  end

  def duplicate_title_heading?(block)
    block&.heading? && block.content_markdown.to_s.strip == "# #{@document.title}"
  end
end

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
  end
end

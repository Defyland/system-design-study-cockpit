class MisconceptionsController < ApplicationController
  def index
    @groups = MisconceptionEvent.group(:misconception_key).count.sort_by { |_key, count| -count }
    @events = MisconceptionEvent.severe_first.includes(:study_document).limit(50)
  end
end

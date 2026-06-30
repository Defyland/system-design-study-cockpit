class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @kind = params[:kind].to_s.presence
    @quick_filter = params[:quick_filter].to_s.presence
    @results = StudySearch.new(q: @query, kind: @kind, quick_filter: @quick_filter).results
    @quick_filters = StudySearch.quick_filters
    @kind_options = ContentKind.library_entries.map { |entry| [ entry.label, entry.key ] }
  end
end

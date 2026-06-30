class ContentReadinessReport
  def initialize(relation: StudyDocument.all)
    @relation = relation
  end

  def ok?
    adapter == "postgresql" &&
      @relation.count >= min_documents &&
      backend_interview_foundations_present?
  end

  def as_json(*)
    {
      status: ok? ? "ok" : "degraded",
      adapter: adapter,
      database: ActiveRecord::Base.connection_db_config.database,
      study_documents: @relation.count,
      reference_documents: @relation.reference_document.count,
      side_tracks: @relation.side_track_overview.count,
      backend_interview_foundations_present: backend_interview_foundations_present?,
      min_documents: min_documents
    }
  end

  private

  def adapter
    ActiveRecord::Base.connection_db_config.adapter
  end

  def min_documents
    Integer(ENV.fetch("STUDY_CONTENT_MIN_DOCUMENTS", Rails.env.production? ? "300" : "1"), 10)
  end

  def backend_interview_foundations_present?
    @relation.side_track_overview.exists?(slug: "backend-interview-foundations")
  end
end

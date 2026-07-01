class ContentReadinessReport
  HEALTHY_STATUSES = %w[ok warning].freeze

  def initialize(relation: StudyDocument.all, sync_runs: ContentSyncRun.all, production: Rails.env.production?)
    @relation = relation
    @sync_runs = sync_runs
    @production = production
  end

  def ok?
    status == "ok"
  end

  def available?
    HEALTHY_STATUSES.include?(status)
  end

  def warning?
    status == "warning"
  end

  def as_json(*)
    {
      status: status,
      adapter: adapter,
      database: ActiveRecord::Base.connection_db_config.database,
      study_documents: study_document_count,
      reference_documents: reference_document_count,
      side_tracks: side_track_count,
      backend_interview_foundations_present: backend_interview_foundations_present?,
      content_bootstrapped: content_bootstrapped?,
      latest_sync_status: latest_sync&.status,
      latest_sync_mode: latest_sync&.source_mode,
      latest_sync_location: latest_sync&.source_location,
      latest_sync_started_at: latest_sync&.started_at,
      latest_sync_finished_at: latest_sync&.finished_at,
      latest_sync_document_count: latest_sync&.document_count,
      latest_sync_error: latest_sync&.error_message,
      last_successful_sync_at: last_successful_sync&.finished_at,
      last_successful_sync_document_count: last_successful_sync&.document_count
    }
  end

  def http_status
    available? ? :ok : :service_unavailable
  end

  private

  def adapter
    ActiveRecord::Base.connection_db_config.adapter
  end

  def status
    return "degraded" unless adapter == "postgresql"
    return "degraded" unless content_bootstrapped?
    return "warning" unless sync_observed?
    return "warning" if latest_sync_failed?

    "ok"
  end

  def backend_interview_foundations_present?
    @relation.side_track_overview.exists?(slug: "backend-interview-foundations")
  end

  def content_bootstrapped?
    study_document_count.positive? && backend_interview_foundations_present?
  end

  def sync_observed?
    return true unless @production

    last_successful_sync.present?
  end

  def latest_sync_failed?
    latest_sync&.failed?
  end

  def latest_sync
    @latest_sync ||= @sync_runs.latest_first.first
  end

  def last_successful_sync
    @last_successful_sync ||= @sync_runs.succeeded.latest_first.first
  end

  def study_document_count
    @study_document_count ||= @relation.count
  end

  def reference_document_count
    @reference_document_count ||= @relation.reference_document.count
  end

  def side_track_count
    @side_track_count ||= @relation.side_track_overview.count
  end
end

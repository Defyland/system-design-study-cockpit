class HealthChecksController < ActionController::Base
  def content
    report = ContentReadinessReport.new
    render json: report.as_json, status: report.ok? ? :ok : :service_unavailable
  end
end

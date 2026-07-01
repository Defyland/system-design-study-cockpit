class HealthChecksController < ActionController::Base
  def content
    report = ContentReadinessReport.new
    render json: report.as_json, status: report.http_status
  end
end

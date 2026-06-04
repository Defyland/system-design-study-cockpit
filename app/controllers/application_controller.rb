class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_cockpit!

  private

  def authenticate_cockpit!
    username = ENV["STUDY_COCKPIT_USERNAME"]
    password = ENV["STUDY_COCKPIT_PASSWORD"]

    raise "Missing STUDY_COCKPIT_PASSWORD in production" if Rails.env.production? && password.blank?
    return if password.blank?

    authenticate_or_request_with_http_basic("Study Cockpit") do |given_username, given_password|
      secure_compare(given_username, username.presence || "study") &&
        secure_compare(given_password, password)
    end
  end

  def secure_compare(value, expected)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(value.to_s),
      Digest::SHA256.hexdigest(expected.to_s)
    )
  end
end

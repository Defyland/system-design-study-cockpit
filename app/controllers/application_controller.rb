class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_cockpit!
  helper_method :cockpit_session_authenticated?

  private

  def authenticate_cockpit!
    password = ENV["STUDY_COCKPIT_PASSWORD"]

    raise "Missing STUDY_COCKPIT_PASSWORD in production" if Rails.env.production? && password.blank?
    return if password.blank?
    return if cockpit_session_authenticated?
    return if request.authorization.present? && authenticate_with_http_basic { |username, secret| valid_cockpit_credentials?(username, secret) }

    if request.authorization.present?
      request_http_basic_authentication("Study Cockpit")
    elsif request.get? && request.format.html?
      session[:cockpit_return_to] = request.fullpath
      redirect_to login_path
    else
      head :unauthorized
    end
  end

  def valid_cockpit_credentials?(username, password)
    valid_username = secure_compare(username, ENV["STUDY_COCKPIT_USERNAME"].presence || "study")
    valid_password = secure_compare(password, ENV["STUDY_COCKPIT_PASSWORD"])
    valid_username && valid_password
  end

  def cockpit_session_authenticated?
    session[:cockpit_auth_version] == cockpit_auth_version
  end

  def cockpit_auth_version
    Digest::SHA256.hexdigest("#{ENV['STUDY_COCKPIT_USERNAME'].presence || 'study'}\0#{ENV['STUDY_COCKPIT_PASSWORD']}")
  end

  def secure_compare(value, expected)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(value.to_s),
      Digest::SHA256.hexdigest(expected.to_s)
    )
  end
end

class CockpitSessionsController < ApplicationController
  skip_before_action :authenticate_cockpit!
  layout "study_cards"

  def new
    redirect_to root_path if cockpit_session_authenticated? || ENV["STUDY_COCKPIT_PASSWORD"].blank?
  end

  def create
    if ENV["STUDY_COCKPIT_PASSWORD"].present? && valid_cockpit_credentials?(params[:username], params[:password])
      destination = url_from(session[:cockpit_return_to]) || root_path
      reset_session
      session[:cockpit_auth_version] = cockpit_auth_version
      redirect_to destination
    else
      flash.now[:alert] = "Credenciais inválidas."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, status: :see_other
  end
end

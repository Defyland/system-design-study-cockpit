class RemindersController < ApplicationController
  def snooze
    Reminder.find(params[:id]).snooze!
    redirect_back fallback_location: root_path
  end

  def dismiss
    Reminder.find(params[:id]).dismiss!
    redirect_back fallback_location: root_path
  end
end

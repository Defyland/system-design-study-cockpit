class StudyPlansController < ApplicationController
  def show
    @plan = InterviewStudyPlan.new.call
  end
end

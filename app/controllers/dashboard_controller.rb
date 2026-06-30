class DashboardController < ApplicationController
  def index
    @chapters = StudyDocument.chapter.in_study_order.includes(:study_progress)
    @current_chapter = next_chapter
    @due_reviews = ReviewSchedule.due.includes(:study_document, :checkpoint).limit(8)
    @reminders = Reminder.visible.ranked.limit(8)
    @progress_counts = StudyProgress.group(:status).count
    @simulation_attempt_count = SimulationAttempt.count
    @misconception_count = MisconceptionEvent.count
    @low_confidence_count = CheckpointAttempt.where(confidence: %w[low medium]).count
    @library_counts = StudyDocument.where(kind: ContentKind.dashboard_keys).group(:kind).count
    @backend_interview_foundations = StudyDocument.side_track_overview.includes(:study_mission).find_by(slug: "backend-interview-foundations")
    @backend_interview_foundations_record_count = @backend_interview_foundations ? @backend_interview_foundations.learning_records.count : 0
    @llm_foundations = StudyDocument.side_track_overview.includes(:study_mission).find_by(slug: "llm-foundations")
    @llm_foundations_record_count = @llm_foundations ? @llm_foundations.learning_records.count : 0
    @interview_plan = InterviewStudyPlan.new.call
  end

  private

  def next_chapter
    @chapters.detect { |chapter| !chapter.progress.mastered? } || @chapters.first
  end
end

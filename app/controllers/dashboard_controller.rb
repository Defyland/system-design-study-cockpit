class DashboardController < ApplicationController
  FEATURED_SIDE_TRACK_SLUGS = %w[backend-interview-foundations llm-foundations].freeze

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
    featured_side_tracks = load_featured_side_tracks
    @backend_interview_foundations = featured_side_tracks["backend-interview-foundations"]
    @backend_interview_foundations_record_count = learning_record_count_for(@backend_interview_foundations)
    @llm_foundations = featured_side_tracks["llm-foundations"]
    @llm_foundations_record_count = learning_record_count_for(@llm_foundations)
    @interview_plan = InterviewStudyPlan.new.call
  end

  private

  def next_chapter
    @chapters.detect { |chapter| !chapter.progress.mastered? } || @chapters.first
  end

  def load_featured_side_tracks
    StudyDocument.side_track_overview
      .where(slug: FEATURED_SIDE_TRACK_SLUGS)
      .includes(:study_mission, :learning_records)
      .index_by(&:slug)
  end

  def learning_record_count_for(side_track)
    side_track ? side_track.learning_records.size : 0
  end
end

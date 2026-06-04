class DashboardController < ApplicationController
  def index
    @chapters = StudyDocument.chapter.in_study_order.includes(:study_progress)
    @current_chapter = next_chapter
    @due_reviews = ReviewSchedule.due.includes(:study_document, :checkpoint).limit(8)
    @reminders = Reminder.visible.ranked.limit(8)
    @progress_counts = StudyProgress.group(:status).count
  end

  private

  def next_chapter
    @chapters.detect { |chapter| !chapter.progress.mastered? } || @chapters.first
  end
end

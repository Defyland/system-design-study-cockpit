class DrillsController < ApplicationController
  def index
    @labs = StudyDocument.lab.in_study_order
    @review_cards = StudyDocument.review_card.in_study_order
    @capstones = StudyDocument.capstone.in_study_order
    @decision_contrasts = StudyDocument.decision_contrast.in_study_order
    @due_reviews = ReviewSchedule.due.includes(:study_document, :checkpoint).limit(12)
  end
end

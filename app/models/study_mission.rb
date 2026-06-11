class StudyMission < ApplicationRecord
  belongs_to :study_document

  validates :why_now, :success_signal, presence: true
  validates :study_document_id, uniqueness: true
  validate :study_document_must_be_side_track_overview

  private

  def study_document_must_be_side_track_overview
    return if study_document.blank? || study_document.side_track_overview?

    errors.add(:study_document, "must be a side track overview")
  end
end

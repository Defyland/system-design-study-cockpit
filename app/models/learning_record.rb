class LearningRecord < ApplicationRecord
  belongs_to :study_document
  belongs_to :related_document, class_name: "StudyDocument", optional: true

  validates :cue, :insight, presence: true
  validate :study_document_must_be_side_track_overview
  validate :related_document_must_belong_to_same_side_track

  private

  def study_document_must_be_side_track_overview
    return if study_document.blank? || study_document.side_track_overview?

    errors.add(:study_document, "must be a side track overview")
  end

  def related_document_must_belong_to_same_side_track
    return if related_document.blank? || study_document.blank?
    return if related_document.side_track_id == study_document.side_track_id

    errors.add(:related_document, "must belong to the same side track")
  end
end

class LearningRecordsController < ApplicationController
  def create
    record = LearningRecord.new(record_params)

    if record.save
      redirect_to side_track_path(record.study_document.slug), notice: "Learning record salvo."
    else
      redirect_to record_fallback_path(record, record_params[:study_document_id]), alert: record.errors.full_messages.to_sentence
    end
  end

  private

  def record_params
    params.expect(learning_record: [ :study_document_id, :related_document_id, :cue, :insight, :unlocks ])
  end

  def record_fallback_path(record, study_document_id)
    track = record.study_document || StudyDocument.find_by(id: study_document_id)
    track ? side_track_path(track.slug) : side_tracks_path
  end
end

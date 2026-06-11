class StudyMissionsController < ApplicationController
  def create
    mission = StudyMission.new(mission_params)

    if mission.save
      redirect_to side_track_path(mission.study_document.slug), notice: "Mission salva."
    else
      redirect_to mission_fallback_path(mission, mission_params[:study_document_id]), alert: mission.errors.full_messages.to_sentence
    end
  end

  def update
    mission = StudyMission.find(params[:id])

    if mission.update(mission_params.except(:study_document_id))
      redirect_to side_track_path(mission.study_document.slug), notice: "Mission atualizada."
    else
      redirect_to side_track_path(mission.study_document.slug), alert: mission.errors.full_messages.to_sentence
    end
  end

  private

  def mission_params
    params.expect(study_mission: [ :study_document_id, :why_now, :success_signal ])
  end

  def mission_fallback_path(mission, study_document_id)
    track = mission.study_document || StudyDocument.find_by(id: study_document_id)
    track ? side_track_path(track.slug) : side_tracks_path
  end
end

require "test_helper"

class StudyPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    reset_study_tables!
  end

  test "renders the 14 day interview plan" do
    StudyDocument.create!(
      kind: "side_track_chapter",
      slug: "backend-interview-foundations-01-dsa-operating-system-and-pattern-selection",
      title: "DSA Operating System and Pattern Selection",
      source_path: "areas/01-metodo-e-entrevistas/backend-interview-foundations/chapters/01-dsa-operating-system-and-pattern-selection.md",
      position: 1,
      body_markdown: "# DSA",
      body_checksum: "dsa"
    )

    get study_plan_path

    assert_response :success
    assert_includes response.body, "Plano de 14 dias"
    assert_includes response.body, "Dia 01"
  end
end

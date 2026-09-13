require "test_helper"

class ArcadeWarmupControllerTest < ActionDispatch::IntegrationTest
  test "warm-up is read-only and uses each existing role's prompts without answer keys" do
    counts = %w[ArcadeLesson.count ArcadeExerciseEvent.count ArcadeStageState.count EnglishArcadeAttempt.count EnglishArcadeSession.count]
    EnglishArcadeResumeInterviewProfile.interview_roles.each do |role|
      card = ArcadeContent.new.items_for("interview", interview_role: role).first
      assert_no_difference(counts) { get arcade_warmup_path, params: { interview_role: role } }
      assert_response :success
      assert_select "[data-controller='arcade-warmup']"
      assert_includes response.body, ERB::Util.html_escape(card.fetch("prompt"))
      assert_not_includes response.body, ERB::Util.html_escape(card.fetch("best_answer"))
      assert_select "form[action='#{arcade_lessons_path}'][method='post'] input[name='lesson[interview_role]'][value='#{role}']"
    end
  end

  test "missing role defaults to full stack and an unknown role fails closed" do
    get arcade_warmup_path
    assert_response :success
    assert_select "input[name='lesson[interview_role]'][value='fullstack']"
    get arcade_warmup_path, params: { interview_role: "unknown" }
    assert_response :unprocessable_entity
  end
end

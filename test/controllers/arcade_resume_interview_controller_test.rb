# frozen_string_literal: true

require "test_helper"

class ArcadeResumeInterviewControllerTest < ActionDispatch::IntegrationTest
  test "interview role rejects an unknown value before lesson creation" do
    assert_no_difference "ArcadeLesson.count" do
      post arcade_lessons_path(format: :json),
        params: { lesson: { target_mode: "interview", interview_role: "platform-astronaut", size: 3 } },
        headers: { "REMOTE_USER" => "resume-role-controller", "ACCEPT" => "application/json" },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_target", JSON.parse(response.body).fetch("error")
  end
end

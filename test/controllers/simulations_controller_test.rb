require "test_helper"

class SimulationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_username = ENV["STUDY_COCKPIT_USERNAME"]
    @original_password = ENV["STUDY_COCKPIT_PASSWORD"]
    ENV["STUDY_COCKPIT_USERNAME"] = "study"
    ENV["STUDY_COCKPIT_PASSWORD"] = "secret"
  end

  teardown do
    ENV["STUDY_COCKPIT_USERNAME"] = @original_username
    ENV["STUDY_COCKPIT_PASSWORD"] = @original_password
  end

  test "evaluate requires cockpit authentication" do
    get evaluate_simulation_path("canary-rollout")

    assert_response :unauthorized
  end

  test "evaluate returns canonical simulation engine output" do
    get evaluate_simulation_path("canary-rollout"),
      params: {
        input_snapshot: {
          users: "120000",
          rollout: "5",
          errorRate: "6",
          latencyP95: "420"
        }
      },
      headers: auth_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "rollback", payload.fetch("outputSnapshot").fetch("recommendedDecision")
    assert_equal 120_000.0, payload.fetch("inputSnapshot").fetch("users")
  end

  private

  def auth_headers
    {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("study", "secret")
    }
  end
end

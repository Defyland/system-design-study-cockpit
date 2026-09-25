require "test_helper"

class CockpitSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_username = ENV["STUDY_COCKPIT_USERNAME"]
    @original_password = ENV["STUDY_COCKPIT_PASSWORD"]
    ENV["STUDY_COCKPIT_USERNAME"] = "study"
    ENV["STUDY_COCKPIT_PASSWORD"] = "test-secret"
  end

  teardown do
    ENV["STUDY_COCKPIT_USERNAME"] = @original_username
    ENV["STUDY_COCKPIT_PASSWORD"] = @original_password
  end

  test "browser access redirects to login while unauthenticated writes are refused" do
    get root_path
    assert_redirected_to login_path
    assert_nil response.headers["WWW-Authenticate"]

    post study_cards_path, params: { topic: "all", mode: "new" }
    assert_response :unauthorized

    get login_path
    assert_response :success
    assert_select "form[action='#{login_path}'][method='post']"
  end

  test "invalid credentials never establish a session and valid login sets a private cookie" do
    post login_path, params: { username: "study", password: "wrong" }
    assert_response :unprocessable_entity
    get root_path
    assert_redirected_to login_path

    post login_path, params: { username: "study", password: "test-secret" }
    assert_redirected_to root_path
    cookie = response.headers.fetch("Set-Cookie")
    assert_includes cookie, "httponly"
    assert_includes cookie, "samesite=lax"
    get root_path
    assert_response :success

    delete logout_path
    assert_redirected_to login_path
    get root_path
    assert_redirected_to login_path
  end

  test "existing Basic Auth clients still work and reject invalid credentials" do
    get root_path, headers: { "Authorization" => basic("study", "test-secret") }
    assert_response :success

    get root_path, headers: { "Authorization" => basic("study", "wrong") }
    assert_response :unauthorized
  end

  test "changing the configured password invalidates an existing cookie" do
    post login_path, params: { username: "study", password: "test-secret" }
    assert_redirected_to root_path
    get root_path
    assert_response :success

    ENV["STUDY_COCKPIT_PASSWORD"] = "rotated-secret"
    get root_path
    assert_redirected_to login_path
    post login_path, params: { username: "study", password: "test-secret" }
    assert_response :unprocessable_entity
    post login_path, params: { username: "study", password: "rotated-secret" }
    assert_redirected_to root_path
  end

  test "login POST requires a CSRF token when forgery protection is enabled" do
    original = CockpitSessionsController.allow_forgery_protection
    CockpitSessionsController.allow_forgery_protection = true

    get login_path
    assert_select "input[name='authenticity_token']"
    post login_path, params: { username: "study", password: "test-secret" }
    assert_response :unprocessable_entity
  ensure
    CockpitSessionsController.allow_forgery_protection = original
  end

  private

  def basic(username, password)
    ActionController::HttpAuthentication::Basic.encode_credentials(username, password)
  end
end

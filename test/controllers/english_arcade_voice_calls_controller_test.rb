require "test_helper"

class EnglishArcadeVoiceCallsControllerTest < ActionDispatch::IntegrationTest
  FakeReservation = Struct.new(:released)

  class FakeBudget
    attr_reader :reservations

    def initialize(reservation: FakeReservation.new(false))
      @reservation = reservation
      @reservations = []
    end

    def reserve(**)
      return unless @reservation

      @reservations << @reservation
      @reservation
    end

    def release(reservation)
      reservation.released = true if reservation
      true
    end
  end

  class FakeClient
    attr_reader :calls

    def initialize(answer: "v=0\r\nfake-answer\r\n")
      @answer = answer
      @calls = []
    end

    def create_call(**arguments)
      @calls << arguments
      @answer
    end
  end

  setup do
    @saved_environment = %w[
      ENGLISH_ARCADE_VOICE_ENABLED OPENAI_API_KEY STUDY_COCKPIT_USERNAME STUDY_COCKPIT_PASSWORD
    ].to_h { |key| [ key, ENV[key] ] }
    ENV["ENGLISH_ARCADE_VOICE_ENABLED"] = "true"
    ENV["OPENAI_API_KEY"] = "sk-test-controller-only"
    ENV.delete("STUDY_COCKPIT_USERNAME")
    ENV.delete("STUDY_COCKPIT_PASSWORD")
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
  end

  teardown do
    @saved_environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "creates a guided call with the authoritative card and safe response headers" do
    session = guided_session
    card = EnglishArcadeSessionBuilder.new.card_for(target: "salesforce", card_key: "salesforce-01-bulkification", session: session)
    budget = FakeBudget.new
    client = FakeClient.new

    with_voice_dependencies(budget, client) do
      post "/english-arcade/voice/calls", params: {
        sdp: "v=0\r\no=offer\r\n", session_id: session.id, card_key: card.key
      }, as: :json
    end

    assert_response :success
    assert_equal "text/sdp", response.media_type
    assert_equal "gpt-realtime-2.1-mini", response.headers.fetch("X-English-Arcade-Voice-Model")
    assert_equal "600", response.headers.fetch("X-English-Arcade-Voice-Call-Limit-Seconds")
    assert_equal "1800", response.headers.fetch("X-English-Arcade-Voice-Daily-Limit-Seconds")
    refute_includes response.body, ENV.fetch("OPENAI_API_KEY")
    call = client.calls.fetch(0)
    assert_equal card.prompt, call.fetch(:instructions).match(/Question: (.*)/)[1]
    assert_includes call.fetch(:instructions), card.answer_text
    assert_equal "gpt-realtime-2.1-mini", call.fetch(:model)
  end

  test "passes the explicitly chosen quality model without upgrading blank requests" do
    session = guided_session
    card_key = "salesforce-01-bulkification"
    budget = FakeBudget.new
    client = FakeClient.new

    with_voice_dependencies(budget, client) do
      post "/english-arcade/voice/calls", params: {
        sdp: "v=0", session_id: session.id, card_key: card_key, model: "gpt-realtime-2.1"
      }, as: :json
    end

    assert_response :success
    assert_equal "gpt-realtime-2.1", client.calls.fetch(0).fetch(:model)
  end

  test "rejects unavailable configuration without resolving a call" do
    ENV.delete("OPENAI_API_KEY")

    post "/english-arcade/voice/calls", params: { sdp: "v=0", session_id: "1", card_key: "x" }, as: :json

    assert_response :service_unavailable
    assert_equal "voice_unavailable", JSON.parse(response.body).fetch("error")
    refute_includes response.body, "sk-test-controller-only"
  end

  test "rejects assessment, another learner, forged card, invalid model, and invalid SDP" do
    assessment = guided_session(metadata: { "experience" => "assessment" })
    post_call(session: assessment, card_key: "salesforce-01-bulkification")
    assert_response :forbidden
    assert_equal "guided_session_required", JSON.parse(response.body).fetch("error")

    other = guided_session(learner_key: "another-learner")
    post_call(session: other, card_key: "salesforce-01-bulkification")
    assert_response :not_found
    assert_equal "session_not_found", JSON.parse(response.body).fetch("error")

    session = guided_session(metadata: { "experience" => "guided", "scheduled_card_key" => "salesforce-01-bulkification" })
    post_call(session: session, card_key: "salesforce-02-governor-limits")
    assert_response :unprocessable_entity
    assert_equal "card_not_found", JSON.parse(response.body).fetch("error")

    post_call(session: session, card_key: "salesforce-01-bulkification", model: "gpt-4o")
    assert_response :unprocessable_entity
    assert_equal "invalid_model", JSON.parse(response.body).fetch("error")

    post_call(session: session, card_key: "salesforce-01-bulkification", sdp: " ")
    assert_response :unprocessable_entity
    assert_equal "invalid_sdp", JSON.parse(response.body).fetch("error")
  end

  test "does not spend an exhausted budget and releases an upstream failure" do
    session = guided_session
    exhausted_budget = FakeBudget.new(reservation: nil)
    client = FakeClient.new
    with_voice_dependencies(exhausted_budget, client) do
      post_call(session: session, card_key: "salesforce-01-bulkification")
    end
    assert_response :too_many_requests
    assert_equal "budget_exhausted", JSON.parse(response.body).fetch("error")
    assert_empty client.calls

    reservation = FakeReservation.new(false)
    budget = FakeBudget.new(reservation: reservation)
    failing_client = Object.new
    failing_client.define_singleton_method(:create_call) { |**| raise EnglishArcadeVoice::RealtimeCallsClient::UpstreamError.new(status: 503) }
    with_voice_dependencies(budget, failing_client) do
      post_call(session: session, card_key: "salesforce-01-bulkification")
    end
    assert_response :bad_gateway
    assert_equal "upstream_unavailable", JSON.parse(response.body).fetch("error")
    assert reservation.released
  end

  private

  def guided_session(learner_key: "anonymous", metadata: { "experience" => "guided" })
    EnglishArcadeSession.create!(
      learner_key: learner_key,
      target: "salesforce",
      mode: "daily",
      duration_seconds: 600,
      started_at: Time.current,
      expires_at: 10.minutes.from_now,
      metadata: metadata
    )
  end

  def post_call(session:, card_key:, model: nil, sdp: "v=0")
    payload = { sdp: sdp, session_id: session.id, card_key: card_key }
    payload[:model] = model if model
    post "/english-arcade/voice/calls", params: payload, as: :json
  end

  def with_voice_dependencies(budget, client)
    controller = EnglishArcadeVoiceCallsController
    previous_budget_factory = controller.voice_budget_factory
    previous_client_factory = controller.voice_client_factory
    controller.voice_budget_factory = ->(_configuration) { budget }
    controller.voice_client_factory = ->(_configuration) { client }
    yield
  ensure
    controller.voice_budget_factory = previous_budget_factory
    controller.voice_client_factory = previous_client_factory
  end
end

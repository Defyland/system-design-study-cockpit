require "test_helper"

class EnglishArcadeVoiceRealtimeCallsClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  class FakeTransport
    attr_reader :url, :headers, :body

    def initialize(response = Response.new("201", "v=0\r\nfake-answer\r\n"))
      @response = response
    end

    def post(url, headers:, body:)
      @url = url
      @headers = headers
      @body = body
      @response
    end
  end

  def setup
    @api_key = "sk-test-only-do-not-send"
    @configuration = EnglishArcadeVoice::Configuration.new(
      env: { "ENGLISH_ARCADE_VOICE_ENABLED" => "true", "OPENAI_API_KEY" => @api_key }
    )
  end

  test "uses the official multipart call contract and returns SDP only" do
    transport = FakeTransport.new
    client = EnglishArcadeVoice::RealtimeCallsClient.new(configuration: @configuration, transport: transport)
    instructions = "Authoritative rehearsal instructions"

    answer = client.create_call(sdp: "v=0\r\no=offer\r\n", model: nil, instructions: instructions)

    assert_equal "v=0\r\nfake-answer\r\n", answer
    assert_equal "https://api.openai.com/v1/realtime/calls", transport.url
    assert_equal "Bearer #{@api_key}", transport.headers.fetch("Authorization")
    assert_match(%r{\Amultipart/form-data; boundary=}, transport.headers.fetch("Content-Type"))
    assert_equal "application/sdp", transport.headers.fetch("Accept")
    assert_includes transport.body, "name=\"sdp\""
    assert_includes transport.body, "name=\"session\""
    assert_includes transport.body, '"model":"gpt-realtime-2.1-mini"'
    assert_includes transport.body, '"output_modalities":["audio"]'
    assert_includes transport.body, '"transcription":{"model":"gpt-4o-mini-transcribe","language":"en"}'
    assert_includes transport.body, '"turn_detection":{"type":"server_vad"}'
    assert_includes transport.body, '"max_output_tokens":800'
    assert_includes transport.body, instructions
    refute_includes transport.body, @api_key
    refute_includes transport.body, '"tools"'
    refute_includes transport.body, '"tracing"'
  end

  test "uses the full quality model only when explicitly selected" do
    transport = FakeTransport.new
    client = EnglishArcadeVoice::RealtimeCallsClient.new(configuration: @configuration, transport: transport)

    client.create_call(sdp: "v=0", model: "gpt-realtime-2.1", instructions: "Use the card.")

    assert_includes transport.body, '"model":"gpt-realtime-2.1"'
  end

  test "maps upstream failures without exposing the upstream body" do
    transport = FakeTransport.new(Response.new("429", "secret provider body"))
    client = EnglishArcadeVoice::RealtimeCallsClient.new(configuration: @configuration, transport: transport)

    error = assert_raises(EnglishArcadeVoice::RealtimeCallsClient::UpstreamError) do
      client.create_call(sdp: "v=0", model: nil, instructions: "Use the card.")
    end

    assert_equal 429, error.status
    refute_includes error.message, "secret provider body"
    refute_includes error.message, @api_key
  end

  test "does not call transport when configuration is unavailable" do
    transport = FakeTransport.new
    configuration = EnglishArcadeVoice::Configuration.new(env: { "ENGLISH_ARCADE_VOICE_ENABLED" => "true" })
    client = EnglishArcadeVoice::RealtimeCallsClient.new(configuration: configuration, transport: transport)

    assert_raises(EnglishArcadeVoice::RealtimeCallsClient::ConfigurationUnavailable) do
      client.create_call(sdp: "v=0", model: nil, instructions: "Use the card.")
    end
    assert_nil transport.url
  end
end

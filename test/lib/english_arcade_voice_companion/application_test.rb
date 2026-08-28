require "test_helper"
require "stringio"
require "english_arcade_voice_companion"

class EnglishArcadeVoiceCompanionApplicationTest < ActiveSupport::TestCase
  class FakeSpeech
    attr_reader :starts, :stops, :cleanup_calls

    def initialize
      @starts = []
      @stops = []
      @cleanup_calls = 0
      @counter = 0
    end

    def status
      { "available" => true, "state" => "idle" }
    end

    def start(language:)
      @counter += 1
      @starts << language
      { "capture_id" => format("%032x", @counter), "state" => "listening" }
    end

    def status_for(capture_id)
      return unless capture_id

      { "capture_id" => capture_id, "state" => "listening", "transcript" => "I would verify the boundary." }
    end

    def stop(capture_id:)
      @stops << capture_id
      { "capture_id" => capture_id, "state" => "stopped", "transcript" => "I would verify the boundary." }
    end

    def cleanup
      @cleanup_calls += 1
    end
  end

  class FakeCodex
    attr_reader :login_calls, :analyses, :cleanup_calls

    def initialize
      @login_calls = []
      @analyses = []
      @cleanup_calls = 0
    end

    def status
      { "state" => "signed_out" }
    end

    def login_start
      @login_calls << true
      { "state" => "login_pending", "authUrl" => "https://auth.example.test/managed" }
    end

    def analyze(**payload)
      @analyses << payload
      EnglishArcadeVoiceCompanion::CodexAppServerClient::OUTPUT_FIELDS.to_h { |field| [ field, "safe #{field}" ] }
    end

    def cleanup
      @cleanup_calls += 1
    end
  end

  setup do
    @speech = FakeSpeech.new
    @codex = FakeCodex.new
    @app = EnglishArcadeVoiceCompanion::Application.new(
      pairing_secret: "a" * 64,
      codex: @codex,
      speech: @speech
    )
  end

  test "requires an exact origin and pairing header on every browser endpoint" do
    status, _headers, body = request("GET", "/v1/status", origin: nil, pair: nil)
    assert_equal 403, status
    assert_equal "origin_not_allowed", body.fetch("error")

    status, _headers, body = request("GET", "/v1/status", origin: "http://evil.localhost:3000", pair: "a" * 64)
    assert_equal 403, status
    assert_equal "origin_not_allowed", body.fetch("error")

    status, _headers, body = request("GET", "/v1/status", pair: "b" * 64)
    assert_equal 401, status
    assert_equal "pairing_required", body.fetch("error")

    status, headers, body = request("GET", "/v1/status", pair: "a" * 64)
    assert_equal 200, status
    assert_equal "http://127.0.0.1:3000", headers.fetch("Access-Control-Allow-Origin")
    assert_equal "ready", body.fetch("companion")
    assert_equal "idle", body.dig("apple", "state")
    assert_equal "signed_out", body.dig("codex", "state")
    refute_includes JSON.generate(body), "a" * 64
    refute_includes JSON.generate(body), "email"
    refute_includes JSON.generate(body), "token"
  end

  test "allows a narrow preflight without accepting wildcard origins" do
    status, headers, body = request("OPTIONS", "/v1/status", origin: "http://localhost:3000", pair: nil)
    assert_equal 204, status
    assert_equal "http://localhost:3000", headers.fetch("Access-Control-Allow-Origin")
    assert_equal "GET, OPTIONS", headers.fetch("Access-Control-Allow-Methods")
    assert_includes headers.fetch("Access-Control-Allow-Headers"), "X-English-Arcade-Pairing"
    assert_empty body

    status, _headers, _body = request("OPTIONS", "/v1/status", origin: "*", pair: nil)
    assert_equal 403, status

    status, _headers, body = request("OPTIONS", "/v1/status", requested_method: "POST", pair: nil)
    assert_equal 405, status
    assert_equal "method_not_allowed", body.fetch("error")
  end

  test "runs the documented managed login and Apple lifecycle without exposing identity" do
    status, _headers, body = request("POST", "/v1/login", body: {})
    assert_equal 200, status
    assert_equal "login_pending", body.fetch("state")
    assert_equal "https://auth.example.test/managed", body.fetch("authUrl")
    refute body.key?("email")
    refute body.key?("token")

    status, _headers, body = request("POST", "/v1/speech/start", body: { "language" => "en-US" })
    assert_equal 200, status
    capture_id = body.fetch("capture_id")
    assert_equal "en-US", @speech.starts.fetch(0)

    status, _headers, body = request("GET", "/v1/speech/status?capture_id=#{capture_id}")
    assert_equal 200, status
    assert_equal "I would verify the boundary.", body.fetch("transcript")

    status, _headers, body = request("POST", "/v1/speech/stop", body: { "capture_id" => capture_id })
    assert_equal 200, status
    assert_equal "stopped", body.fetch("state")
    assert_equal [ capture_id ], @speech.stops
  end

  test "accepts only bounded JSON analysis context and cleans both children" do
    payload = {
      "question" => "How would you protect a boundary?",
      "answer" => "I would verify the boundary before changing it.",
      "context" => "Visible authored context",
      "transcript" => "I would verify the boundary."
    }
    status, _headers, body = request("POST", "/v1/analyze", body: payload)
    assert_equal 200, status
    assert_equal "safe summary", body.dig("analysis", "summary")
    assert_equal payload.transform_keys(&:to_sym), @codex.analyses.fetch(0)

    status, _headers, body = request("POST", "/v1/analyze", body: payload.merge("transcript" => "x" * (64 * 1024 + 1)))
    assert_equal 422, status
    assert_equal "invalid_request", body.fetch("error")

    status, _headers, body = request("POST", "/v1/cleanup", body: {})
    assert_equal 200, status
    assert_equal "clean", body.fetch("state")
    assert_equal 1, @speech.cleanup_calls
    assert_equal 1, @codex.cleanup_calls

    status, _headers, body = request("POST", "/v1/cleanup", body: {})
    assert_equal 200, status
    assert_equal "clean", body.fetch("state")
    assert_equal 2, @speech.cleanup_calls
    assert_equal 2, @codex.cleanup_calls
  end

  test "rejects non-JSON, unknown methods, missing captures, and oversized bodies generically" do
    status, _headers, body = request("POST", "/v1/cleanup", raw_body: "x", content_type: "application/x-www-form-urlencoded")
    assert_equal 415, status
    assert_equal "unsupported_media_type", body.fetch("error")

    status, _headers, body = request("DELETE", "/v1/status")
    assert_equal 404, status
    assert_equal "not_found", body.fetch("error")

    status, _headers, body = request("GET", "/v1/speech/status?capture_id=not-valid")
    assert_equal 422, status
    assert_equal "invalid_request", body.fetch("error")

    status, _headers, body = request("POST", "/v1/cleanup", raw_body: "x" * (128 * 1024 + 1))
    assert_equal 413, status
    assert_equal "body_too_large", body.fetch("error")
  end

  test "does not serve requests after explicit process cleanup" do
    @app.close

    status, _headers, body = request("GET", "/v1/status")
    assert_equal 503, status
    assert_equal "companion_unavailable", body.fetch("error")
  end

  private

  def request(method, path, origin: "http://127.0.0.1:3000", pair: "a" * 64, body: nil, raw_body: nil, content_type: "application/json", requested_method: nil)
    env = Rack::MockRequest.env_for(path, method: method)
    env["HTTP_ORIGIN"] = origin if origin
    env["HTTP_X_ENGLISH_ARCADE_PAIRING"] = pair if pair
    env["HTTP_ACCESS_CONTROL_REQUEST_METHOD"] = requested_method if requested_method
    raw = raw_body || (body.nil? ? "" : JSON.generate(body))
    env["CONTENT_TYPE"] = content_type if content_type
    env["CONTENT_LENGTH"] = raw.bytesize.to_s
    env["rack.input"] = StringIO.new(raw)
    status, headers, chunks = @app.call(env)
    parsed = chunks.join
    [ status, headers, parsed.empty? ? {} : JSON.parse(parsed) ]
  end
end

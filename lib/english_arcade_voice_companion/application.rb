# frozen_string_literal: true

require "openssl"
require "securerandom"

module EnglishArcadeVoiceCompanion
  class Application
    PAIR_HEADER = "HTTP_X_ENGLISH_ARCADE_PAIRING"
    PAIRING_HEADER = "X-English-Arcade-Pairing"
    DEFAULT_PORT = 43_129
    MAX_JSON_BYTES = 128 * 1024
    MAX_QUERY_BYTES = 512

    ROUTES = {
      [ "GET", "/v1/status" ] => :status,
      [ "POST", "/v1/login" ] => :login_start,
      [ "POST", "/v1/speech/start" ] => :speech_start,
      [ "GET", "/v1/speech/status" ] => :speech_status,
      [ "POST", "/v1/speech/stop" ] => :speech_stop,
      [ "POST", "/v1/analyze" ] => :analysis,
      [ "POST", "/v1/cleanup" ] => :cleanup
    }.freeze

    CORS_HEADERS = "Content-Type, Accept, #{PAIRING_HEADER}".freeze

    def self.build(env: ENV, **options)
      new(env: env, **options)
    end

    attr_reader :pairing_secret, :origin_allowlist, :codex, :speech

    def initialize(env: ENV, origin_allowlist: nil, pairing_secret: nil, codex: nil, speech: nil, clock: nil)
      @origin_allowlist = origin_allowlist || OriginAllowlist.new(env["ENGLISH_ARCADE_VOICE_COMPANION_ORIGINS"])
      @pairing_secret = pairing_secret || SecureRandom.hex(32)
      @codex = codex || CodexAppServerClient.new
      @speech = speech || AppleSpeechService.new(env: env)
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @analysis_service = AnalysisService.new(codex: @codex)
      @closed = false
    end

    def call(env)
      return closed_response if @closed

      request_method = env["REQUEST_METHOD"].to_s
      path = env["PATH_INFO"].to_s
      route = ROUTES[[ request_method, path ]]
      return handle_options(env) if request_method == "OPTIONS"
      return json_error("not_found", 404, env) unless route
      return json_error("origin_not_allowed", 403, env) unless origin_allowed?(env)
      return json_error("pairing_required", 401, env) unless paired?(env)

      payload = request_payload(env, method: request_method)
      add_origin_header(send(route, env, payload), env["HTTP_ORIGIN"])
    rescue RequestError => error
      json_error(error.code, error.status, env)
    rescue AnalysisService::InvalidInput, AppleSpeechService::InvalidRequest
      json_error("invalid_request", 422, env)
    rescue AnalysisService::Unavailable, AppleSpeechService::Unavailable, CodexAppServerClient::Unavailable
      json_error("companion_unavailable", 503, env)
    rescue StandardError
      # Never serialize exception text: it may contain a path, transcript,
      # request header, or process detail.
      json_error("companion_unavailable", 503, env)
    end

    def close
      return if @closed

      @closed = true
      @speech.cleanup
      @codex.cleanup
      true
    rescue StandardError
      true
    end

    private

    class RequestError < StandardError
      attr_reader :code, :status

      def initialize(code, status)
        @code = code
        @status = status
        super(code.to_s)
      end
    end

    def handle_options(env)
      origin = env["HTTP_ORIGIN"].to_s
      return json_error("origin_not_allowed", 403) unless @origin_allowlist.allowed?(origin)
      path = env["PATH_INFO"].to_s
      return json_error("not_found", 404, env) unless ROUTES.keys.any? { |_method, route_path| route_path == path }

      requested_method = env["HTTP_ACCESS_CONTROL_REQUEST_METHOD"].to_s
      allowed_methods = ROUTES.keys.filter_map { |method, route_path| method if route_path == path }.uniq
      if !requested_method.empty? && !allowed_methods.include?(requested_method)
        return json_error("method_not_allowed", 405, env)
      end

      headers = base_headers.merge(
        "Access-Control-Allow-Origin" => origin,
        "Access-Control-Allow-Methods" => (allowed_methods + [ "OPTIONS" ]).join(", "),
        "Access-Control-Allow-Headers" => CORS_HEADERS,
        "Access-Control-Max-Age" => "300"
      )
      [ 204, headers, [] ]
    end

    def status(_env, _payload)
      apple = @speech.status
      apple_state = apple["state"].to_s
      result = {
        "companion" => "ready",
        "apple" => {
          "available" => apple["available"] == true,
          "state" => %w[idle starting listening error].include?(apple_state) ? apple_state : "unavailable"
        },
        "codex" => { "state" => coarse_codex_state(@codex.status.fetch("state", "unavailable")) }
      }
      json_response(result)
    end

    def login_start(_env, _payload)
      result = @codex.login_start
      json_response({ "ok" => true, "state" => result.fetch("state"), "authUrl" => result.fetch("authUrl") })
    end

    def speech_start(_env, payload)
      language = payload.fetch("language", AppleSpeechService::DEFAULT_LANGUAGE)
      result = @speech.start(language: language)
      json_response("ok" => true, "capture_id" => result.fetch("capture_id"), "state" => result.fetch("state"))
    end

    def speech_status(env, _payload)
      query = env["QUERY_STRING"].to_s
      raise RequestError.new("invalid_request", 422) if query.bytesize > MAX_QUERY_BYTES

      params = Rack::Utils.parse_query(query)
      raise RequestError.new("invalid_request", 422) unless valid_capture_id?(params["capture_id"])
      result = @speech.status_for(params["capture_id"])
      raise RequestError.new("capture_not_found", 404) unless result

      json_response(result)
    end

    def speech_stop(_env, payload)
      raise RequestError.new("invalid_request", 422) unless valid_capture_id?(payload["capture_id"])
      result = @speech.stop(capture_id: payload["capture_id"])
      raise RequestError.new("capture_not_found", 404) unless result

      json_response(result)
    end

    def analysis(_env, payload)
      required = %w[question answer transcript]
      raise RequestError.new("invalid_request", 422) unless required.all? { |key| payload[key].is_a?(String) }
      context = payload.fetch("context", "")
      raise RequestError.new("invalid_request", 422) unless context.is_a?(String)

      result = @analysis_service.call(
        question: payload.fetch("question"),
        answer: payload.fetch("answer"),
        context: context,
        transcript: payload.fetch("transcript")
      )
      json_response({ "ok" => true, "analysis" => result })
    end

    def cleanup(_env, _payload)
      @speech.cleanup
      @codex.cleanup
      json_response("ok" => true, "state" => "clean")
    end

    def request_payload(env, method:)
      return {} if method == "GET"

      content_type = env["CONTENT_TYPE"].to_s
      unless content_type.empty? || content_type.downcase.start_with?("application/json")
        raise RequestError.new("unsupported_media_type", 415)
      end

      content_length = env["CONTENT_LENGTH"].to_i
      raise RequestError.new("body_too_large", 413) if content_length > MAX_JSON_BYTES

      input = env["rack.input"]
      body = input ? input.read(MAX_JSON_BYTES + 1).to_s : ""
      raise RequestError.new("body_too_large", 413) if body.bytesize > MAX_JSON_BYTES
      return {} if body.strip.empty?

      parsed = JSON.parse(body)
      raise RequestError.new("invalid_request", 422) unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise RequestError.new("invalid_request", 422)
    end

    def coarse_codex_state(value)
      state = value.to_s
      %w[signed_out login_pending signed_in unavailable].include?(state) ? state : "unavailable"
    end

    def valid_capture_id?(value)
      value.is_a?(String) && value.match?(/\A[0-9a-f]{32}\z/)
    end

    def origin_allowed?(env)
      @origin_allowlist.allowed?(env["HTTP_ORIGIN"])
    end

    def paired?(env)
      supplied = env[PAIR_HEADER].to_s
      return false unless supplied.bytesize == @pairing_secret.bytesize

      OpenSSL.fixed_length_secure_compare(supplied, @pairing_secret)
    rescue ArgumentError
      false
    end

    def json_response(payload, status = 200)
      body = JSON.generate(payload)
      raise RequestError.new("response_too_large", 500) if body.bytesize > MAX_JSON_BYTES

      [ status, base_headers, [ body ] ]
    end

    def json_error(code, status, env = nil)
      body = JSON.generate("error" => code.to_s)
      headers = base_headers
      origin = env && env["HTTP_ORIGIN"].to_s
      headers["Access-Control-Allow-Origin"] = origin if origin && @origin_allowlist.allowed?(origin)
      [ status, headers, [ body ] ]
    end

    def add_origin_header(response, origin)
      response[1]["Access-Control-Allow-Origin"] = origin.to_s if @origin_allowlist.allowed?(origin)
      response
    end

    def base_headers
      {
        "Content-Type" => "application/json; charset=utf-8",
        "Cache-Control" => "no-store",
        "Vary" => "Origin"
      }
    end

    def closed_response
      json_error("companion_unavailable", 503)
    end
  end
end

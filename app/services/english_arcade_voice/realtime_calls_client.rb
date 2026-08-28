# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

module EnglishArcadeVoice
  # Narrow stdlib transport for the official WebRTC Calls endpoint. The
  # transport is injectable so controller/service tests never perform a paid
  # request or depend on the network.
  class RealtimeCallsClient
    ENDPOINT = "https://api.openai.com/v1/realtime/calls"
    ENDPOINT_URI = URI.parse(ENDPOINT).freeze
    MULTIPART_FIELD_SDP = "sdp"
    MULTIPART_FIELD_SESSION = "session"

    Request = Struct.new(:method, :url, :headers, :body, keyword_init: true)

    class UpstreamError < StandardError
      attr_reader :status

      def initialize(status: nil)
        @status = status
        super("Realtime voice provider unavailable")
      end
    end

    class InvalidRequest < StandardError; end
    class ConfigurationUnavailable < StandardError; end

    class NetHttpTransport
      def post(url, headers:, body:)
        uri = URI.parse(url.to_s)
        raise ArgumentError unless uri == ENDPOINT_URI

        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |name, value| request[name] = value.to_s }
        request.body = body

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 45
        http.write_timeout = 15 if http.respond_to?(:write_timeout=)
        http.request(request)
      rescue StandardError => error
        raise error if error.is_a?(ArgumentError)

        raise UpstreamError
      end
    end

    attr_reader :configuration, :transport

    def initialize(configuration: Configuration.new, transport: nil, http_transport: nil, transport_factory: nil)
      @configuration = configuration
      @transport_factory = transport_factory
      @transport = transport || http_transport || NetHttpTransport.new
    end

    def create_call(sdp:, model:, instructions:)
      ensure_configuration!
      selected_model = configuration.model_for(model)
      raise InvalidRequest, "invalid model" unless selected_model

      offer = sdp.to_s
      raise InvalidRequest, "invalid sdp" if offer.strip.empty? || offer.bytesize > 256.kilobytes
      prompt = instructions.to_s
      raise InvalidRequest, "missing instructions" if prompt.strip.empty?

      boundary = "EnglishArcadeVoice#{SecureRandom.hex(16)}"
      session = session_configuration(model: selected_model, instructions: prompt)
      body = multipart_body(boundary: boundary, sdp: offer, session: session)
      headers = {
        "Authorization" => "Bearer #{configuration.api_key}",
        "Content-Type" => "multipart/form-data; boundary=#{boundary}",
        "Accept" => "application/sdp"
      }

      response = perform_post(headers: headers, body: body)
      status = response_status(response)
      raise UpstreamError.new(status: status) unless status && status.between?(200, 299)

      answer = response_body(response).to_s
      raise UpstreamError.new(status: status) if answer.strip.empty?

      answer
    rescue UpstreamError, InvalidRequest, ConfigurationUnavailable
      raise
    rescue StandardError
      # Do not expose transport exception text, which can contain an upstream
      # body, URL details, or other request-facing data.
      raise UpstreamError
    end

    alias call create_call

    def session_configuration(model:, instructions:)
      {
        "type" => "realtime",
        "model" => model,
        "output_modalities" => [ "audio" ],
        "audio" => {
          "input" => {
            "format" => { "type" => "audio/pcm", "rate" => 24_000 },
            "transcription" => { "model" => "gpt-4o-mini-transcribe", "language" => "en" },
            "turn_detection" => { "type" => "server_vad" }
          },
          "output" => {
            "format" => { "type" => "audio/pcm", "rate" => 24_000 }
          }
        },
        "instructions" => instructions,
        "max_output_tokens" => configuration.max_output_tokens,
        "reasoning" => { "effort" => "low" }
      }
    end

    private

    def ensure_configuration!
      raise ConfigurationUnavailable unless configuration.available?
    end

    def transport_instance
      return transport unless @transport_factory

      arity = @transport_factory.method(:call).arity
      arity.zero? ? @transport_factory.call : @transport_factory.call(ENDPOINT)
    rescue NameError
      @transport_factory.call
    end

    def perform_post(headers:, body:)
      client = transport_instance
      if client.respond_to?(:post)
        request = Request.new(method: :post, url: ENDPOINT, headers: headers, body: body)
        client.method(:post).arity == 1 ? client.post(request) : client.post(ENDPOINT, headers: headers, body: body)
      elsif client.respond_to?(:call)
        request = Request.new(method: :post, url: ENDPOINT, headers: headers, body: body)
        parameters = client.method(:call).parameters
        accepts_keywords = parameters.any? { |kind, _name| %i[key keyreq keyrest].include?(kind) }
        accepts_keywords ? client.call(method: :post, url: ENDPOINT, headers: headers, body: body) : client.call(request)
      else
        raise ArgumentError, "unsupported transport"
      end
    rescue UpstreamError
      raise
    rescue StandardError
      raise UpstreamError
    end

    def response_status(response)
      value = if response.respond_to?(:code)
        response.code
      elsif response.respond_to?(:status)
        response.status
      elsif response.is_a?(Hash)
        response[:status] || response["status"] || response[:code] || response["code"]
      end
      value.is_a?(String) ? Integer(value, 10) : Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def response_body(response)
      return response.body if response.respond_to?(:body)
      return response[:body] || response["body"] if response.is_a?(Hash)

      response.to_s
    end

    def multipart_body(boundary:, sdp:, session:)
      parts = [
        [ MULTIPART_FIELD_SDP, sdp ],
        [ MULTIPART_FIELD_SESSION, JSON.generate(session) ]
      ]
      parts.map do |name, value|
        "--#{boundary}\r\n" \
          "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n" \
          "#{value}\r\n"
      end.join + "--#{boundary}--\r\n"
    end
  end
end

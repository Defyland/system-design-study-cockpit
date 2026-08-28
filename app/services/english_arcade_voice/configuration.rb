# frozen_string_literal: true

module EnglishArcadeVoice
  # Runtime-only configuration for the optional voice rehearsal. Keeping this
  # object independent from Rails configuration makes feature/key fallback and
  # duration limits deterministic in tests and easy to audit locally.
  class Configuration
    DEFAULT_MODEL = "gpt-realtime-2.1-mini"
    QUALITY_MODEL = "gpt-realtime-2.1"
    ALLOWED_MODELS = [ DEFAULT_MODEL, QUALITY_MODEL ].freeze

    MIN_DURATION_SECONDS = 10.minutes.to_i
    MAX_DURATION_SECONDS = 30.minutes.to_i
    DEFAULT_CALL_DURATION_SECONDS = MIN_DURATION_SECONDS
    DEFAULT_DAILY_DURATION_SECONDS = MAX_DURATION_SECONDS

    DEFAULT_MAX_OUTPUT_TOKENS = 800
    MIN_MAX_OUTPUT_TOKENS = 128
    MAX_MAX_OUTPUT_TOKENS = 2_000

    ENV_DURATION_KEYS = {
      call: %w[
        ENGLISH_ARCADE_VOICE_CALL_DURATION_SECONDS
        ENGLISH_ARCADE_VOICE_PER_CALL_DURATION_SECONDS
        ENGLISH_ARCADE_VOICE_PER_CALL_SECONDS
        ENGLISH_ARCADE_VOICE_MAX_CALL_SECONDS
        ENGLISH_ARCADE_VOICE_MAX_DURATION_SECONDS
      ],
      daily: %w[
        ENGLISH_ARCADE_VOICE_DAILY_DURATION_SECONDS
        ENGLISH_ARCADE_VOICE_DAILY_MAX_SECONDS
        ENGLISH_ARCADE_VOICE_DAILY_MAX_DURATION_SECONDS
        ENGLISH_ARCADE_VOICE_MAX_DAILY_SECONDS
      ]
    }.freeze

    attr_reader :env

    def initialize(env: ENV)
      @env = env
    end

    def enabled?
      truthy?(env["ENGLISH_ARCADE_VOICE_ENABLED"])
    end

    def api_key
      env["OPENAI_API_KEY"].to_s.strip.presence
    end

    def available?
      enabled? && api_key.present?
    end

    def default_model
      DEFAULT_MODEL
    end

    def quality_model
      QUALITY_MODEL
    end

    def allowed_models
      ALLOWED_MODELS
    end

    # A blank request is deliberately the lower-cost mini model. The quality
    # model is reachable only by an explicit, allow-listed model value; there
    # is no fallback that silently upgrades a caller.
    def model_for(requested)
      value = requested.to_s.strip
      value = default_model if value.blank?
      allowed_models.include?(value) ? value : nil
    end

    def valid_model?(requested)
      model_for(requested).present?
    end

    def call_duration_seconds
      bounded_duration(:call, DEFAULT_CALL_DURATION_SECONDS)
    end

    alias per_call_duration_seconds call_duration_seconds

    def daily_duration_seconds
      [ bounded_duration(:daily, DEFAULT_DAILY_DURATION_SECONDS), call_duration_seconds ].max
    end

    alias daily_max_seconds daily_duration_seconds

    def max_output_tokens
      raw = env["ENGLISH_ARCADE_VOICE_MAX_OUTPUT_TOKENS"]
      value = raw.is_a?(String) ? Integer(raw, 10) : Integer(raw)
      value.clamp(MIN_MAX_OUTPUT_TOKENS, MAX_MAX_OUTPUT_TOKENS)
    rescue ArgumentError, TypeError
      DEFAULT_MAX_OUTPUT_TOKENS
    end

    private

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end

    def bounded_duration(kind, fallback)
      raw = ENV_DURATION_KEYS.fetch(kind).lazy.map { |key| env[key] }.find(&:present?)
      value = raw.is_a?(String) ? Integer(raw, 10) : Integer(raw)
      value.clamp(MIN_DURATION_SECONDS, MAX_DURATION_SECONDS)
    rescue ArgumentError, TypeError
      fallback
    end
  end
end

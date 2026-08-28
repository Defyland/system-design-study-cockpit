# frozen_string_literal: true

require "uri"

module EnglishArcadeVoiceCompanion
  class OriginAllowlist
    DEFAULT_ORIGINS = %w[http://localhost:3000 http://127.0.0.1:3000].freeze

    attr_reader :origins

    def initialize(value = nil)
      entries = value.to_s.split(",", -1).map(&:strip) if value
      entries = DEFAULT_ORIGINS if entries.nil? || entries.empty? || entries.all?(&:empty?)
      @origins = entries.filter_map { |entry| canonical_origin(entry) }.uniq.freeze
    end

    def allowed?(origin)
      value = origin.to_s
      !value.empty? && value != "null" && origins.include?(value)
    end

    private

    def canonical_origin(value)
      return if value.empty? || value == "null" || value.include?("*")

      uri = URI.parse(value)
      return unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
      return unless uri.user.nil? && uri.password.nil?
      return unless uri.path.to_s.empty? || uri.path == "/"
      return unless uri.query.nil? && uri.fragment.nil?

      normalized = "#{uri.scheme.downcase}://#{uri.host.downcase}"
      normalized += ":#{uri.port}" unless default_port?(uri)
      # An origin with a trailing slash is accepted as configuration syntax but
      # requests are compared against the browser's exact Origin value.
      normalized
    rescue URI::InvalidURIError
      nil
    end

    def default_port?(uri)
      (uri.scheme.downcase == "http" && uri.port == 80) ||
        (uri.scheme.downcase == "https" && uri.port == 443)
    end
  end
end

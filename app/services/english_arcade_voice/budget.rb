# frozen_string_literal: true

require "digest"

module EnglishArcadeVoice
  # Reserves the complete configured call allowance before creating a paid
  # upstream call. Only a short-lived numeric counter lives in the cache; no
  # audio, transcript, card text, or prompt is persisted.
  class Budget
    Reservation = Struct.new(:key, :seconds, :learner_key, :day, :expires_in, :released, keyword_init: true)

    attr_reader :configuration, :cache, :clock

    def initialize(configuration: Configuration.new, cache: default_cache, clock: -> { Time.current })
      @configuration = configuration
      @cache = cache
      @clock = clock
    end

    def reserve(learner_key:, seconds: configuration.call_duration_seconds, at: nil)
      requested_seconds = seconds.is_a?(String) ? Integer(seconds, 10) : Integer(seconds)
      return if requested_seconds <= 0

      # Internal callers cannot use a larger reservation to bypass the
      # per-call product ceiling. The controller normally uses the full
      # configured allowance, which is the conservative cost bound.
      requested_seconds = [ requested_seconds, configuration.call_duration_seconds ].min
      return unless cache.respond_to?(:increment) && cache.respond_to?(:decrement)

      timestamp = at || clock.call
      day = timestamp.to_date
      key = key_for(learner_key, day)
      expires_in = expiry_for(day, timestamp)
      total = cache.increment(key, requested_seconds, expires_in: expires_in)
      return unless total.is_a?(Numeric)

      if total > configuration.daily_duration_seconds
        rollback = cache.decrement(key, requested_seconds, expires_in: expires_in)
        return unless rollback.is_a?(Numeric)

        return
      end

      Reservation.new(
        key: key,
        seconds: requested_seconds,
        learner_key: learner_key.to_s,
        day: day,
        expires_in: expires_in,
        released: false
      )
    rescue StandardError
      nil
    end

    def release(reservation)
      return false unless reservation.is_a?(Reservation)

      return false if reservation.released

      result = cache.decrement(
        reservation.key,
        reservation.seconds.to_i,
        expires_in: reservation.expires_in
      )
      return false unless result.is_a?(Numeric)

      reservation.released = true

      true
    rescue StandardError
      false
    end

    alias release! release

    def used(learner_key:, at: nil)
      timestamp = at || clock.call
      cache.read(key_for(learner_key, timestamp.to_date)).to_i
    end

    def remaining(learner_key:, at: nil)
      [ configuration.daily_duration_seconds - used(learner_key: learner_key, at: at), 0 ].max
    end

    def key_for(learner_key, day = (clock.call.to_date))
      learner_digest = Digest::SHA256.hexdigest(learner_key.to_s)[0, 32]
      "english-arcade-voice:budget:v1:#{learner_digest}:#{day.iso8601}"
    end

    private

    def default_cache
      Rails.cache
    end

    def expiry_for(day, timestamp)
      [ (day + 1).to_time - timestamp, 1.hour.to_i ].max
    end
  end
end

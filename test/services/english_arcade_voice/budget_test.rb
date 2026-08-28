require "test_helper"

class EnglishArcadeVoiceBudgetTest < ActiveSupport::TestCase
  class FakeCache
    attr_reader :increments, :decrements

    def initialize
      @values = {}
      @increments = []
      @decrements = []
    end

    def read(key)
      @values[key]
    end

    def increment(key, amount = 1, expires_in: nil)
      @values[key] = @values.fetch(key, 0) + amount
      @increments << [ key, amount, expires_in ]
      @values[key]
    end

    def decrement(key, amount = 1, expires_in: nil)
      @values[key] = @values.fetch(key, 0) - amount
      @decrements << [ key, amount, expires_in ]
      @values[key]
    end
  end

  def setup
    @cache = FakeCache.new
    @clock_time = Time.utc(2026, 8, 28, 12)
    @configuration = EnglishArcadeVoice::Configuration.new(
      env: {
        "ENGLISH_ARCADE_VOICE_CALL_DURATION_SECONDS" => "600",
        "ENGLISH_ARCADE_VOICE_DAILY_DURATION_SECONDS" => "1200"
      }
    )
    @budget = EnglishArcadeVoice::Budget.new(
      configuration: @configuration,
      cache: @cache,
      clock: -> { @clock_time }
    )
  end

  test "scopes reservations by learner and day, and releases failed calls" do
    first = @budget.reserve(learner_key: "learner-a")
    second = @budget.reserve(learner_key: "learner-a")
    assert first
    assert second
    assert_nil @budget.reserve(learner_key: "learner-a")
    assert_equal 0, @budget.remaining(learner_key: "learner-a")

    assert @budget.release(first)
    assert_equal 600, @budget.remaining(learner_key: "learner-a")
    assert_not @budget.release(first)

    other_learner = @budget.reserve(learner_key: "learner-b")
    assert other_learner
    @clock_time += 1.day
    next_day = @budget.reserve(learner_key: "learner-a")
    assert next_day
    assert_equal 600, @budget.used(learner_key: "learner-a", at: @clock_time)
  end

  test "never reserves more than the configured per-call allowance" do
    reservation = @budget.reserve(learner_key: "learner-a", seconds: 1_800)

    assert_equal 600, reservation.seconds
    assert_equal 600, @budget.used(learner_key: "learner-a")
  end

  test "distinct budget instances cannot oversubscribe a one-call daily limit" do
    configuration = EnglishArcadeVoice::Configuration.new(
      env: {
        "ENGLISH_ARCADE_VOICE_CALL_DURATION_SECONDS" => "600",
        "ENGLISH_ARCADE_VOICE_DAILY_DURATION_SECONDS" => "600"
      }
    )
    first_budget = EnglishArcadeVoice::Budget.new(configuration: configuration, cache: @cache, clock: -> { @clock_time })
    second_budget = EnglishArcadeVoice::Budget.new(configuration: configuration, cache: @cache, clock: -> { @clock_time })

    assert first_budget.reserve(learner_key: "learner-a")
    assert_nil second_budget.reserve(learner_key: "learner-a")
    assert_equal 600, first_budget.used(learner_key: "learner-a")
    assert_equal 1, @cache.decrements.length
  end

  test "fails closed when the cache does not provide atomic adjustment" do
    cache = Object.new
    budget = EnglishArcadeVoice::Budget.new(configuration: @configuration, cache: cache, clock: -> { @clock_time })

    assert_nil budget.reserve(learner_key: "learner-a")
  end
end

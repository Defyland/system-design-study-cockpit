require "test_helper"

class EnglishArcadeVoiceConfigurationTest < ActiveSupport::TestCase
  test "requires both the feature flag and an API key" do
    assert_not EnglishArcadeVoice::Configuration.new(env: {}).available?
    assert_not EnglishArcadeVoice::Configuration.new(env: { "ENGLISH_ARCADE_VOICE_ENABLED" => "true" }).available?
    assert EnglishArcadeVoice::Configuration.new(
      env: { "ENGLISH_ARCADE_VOICE_ENABLED" => "on", "OPENAI_API_KEY" => "test-key" }
    ).available?
  end

  test "keeps mini as the default and allows the quality model only explicitly" do
    configuration = EnglishArcadeVoice::Configuration.new(
      env: { "ENGLISH_ARCADE_VOICE_ENABLED" => "1", "OPENAI_API_KEY" => "test-key" }
    )

    assert_equal "gpt-realtime-2.1-mini", configuration.default_model
    assert_equal "gpt-realtime-2.1-mini", configuration.model_for(nil)
    assert_equal "gpt-realtime-2.1-mini", configuration.model_for("")
    assert_equal "gpt-realtime-2.1", configuration.model_for("gpt-realtime-2.1")
    assert_nil configuration.model_for("gpt-realtime")
    assert_nil configuration.model_for("gpt-4o")
  end

  test "clamps durations and output tokens to product bounds" do
    configuration = EnglishArcadeVoice::Configuration.new(
      env: {
        "ENGLISH_ARCADE_VOICE_CALL_DURATION_SECONDS" => "1",
        "ENGLISH_ARCADE_VOICE_DAILY_DURATION_SECONDS" => "999999",
        "ENGLISH_ARCADE_VOICE_MAX_OUTPUT_TOKENS" => "999999"
      }
    )

    assert_equal 10.minutes.to_i, configuration.call_duration_seconds
    assert_equal 30.minutes.to_i, configuration.daily_duration_seconds
    assert_equal 2_000, configuration.max_output_tokens
  end

  test "never lets the daily allowance fall below one configured call" do
    configuration = EnglishArcadeVoice::Configuration.new(
      env: {
        "ENGLISH_ARCADE_VOICE_CALL_DURATION_SECONDS" => "1800",
        "ENGLISH_ARCADE_VOICE_DAILY_DURATION_SECONDS" => "600"
      }
    )

    assert_equal 1_800, configuration.call_duration_seconds
    assert_equal 1_800, configuration.daily_duration_seconds
  end
end

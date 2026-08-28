# frozen_string_literal: true

# The companion deliberately uses only Ruby's standard library plus Rack,
# which is already supplied by Rails/Puma. It is a separate loopback process;
# Rails never receives its pairing secret, audio, transcript, or Codex auth.
require "json"
require "rack"

require_relative "english_arcade_voice_companion/origin_allowlist"
require_relative "english_arcade_voice_companion/prompt"
require_relative "english_arcade_voice_companion/codex_app_server_client"
require_relative "english_arcade_voice_companion/apple_speech_service"
require_relative "english_arcade_voice_companion/analysis_service"
require_relative "english_arcade_voice_companion/application"

module EnglishArcadeVoiceCompanion
  VERSION = "0.1.0"
end

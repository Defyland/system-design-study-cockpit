# frozen_string_literal: true

require_relative "../lib/english_arcade_voice_companion"

$english_arcade_voice_companion = EnglishArcadeVoiceCompanion::Application.build

# The secret is intentionally emitted once to the local terminal only. It is
# never part of a Rack response, query string, request body, or log line.
$stderr.puts("English Arcade voice companion pairing secret: #{$english_arcade_voice_companion.pairing_secret}")

at_exit do
  $english_arcade_voice_companion&.close
end

run $english_arcade_voice_companion

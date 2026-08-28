require "test_helper"
require "fileutils"
require "tempfile"
require "english_arcade_voice_companion"

class EnglishArcadeVoiceCompanionAppleSpeechServiceTest < ActiveSupport::TestCase
  class FakeProcess
    attr_reader :writes
    attr_accessor :terminated, :transcript, :error_code

    def initialize
      @writes = []
      @records = []
      @terminated = false
      @transcript = "I would verify the boundary."
      @error_code = nil
    end

    def write(value)
      @writes << JSON.parse(value)
      if @writes.last["type"] == "start"
        @records << { "type" => "state", "state" => "listening" }
        @records << { "type" => "transcript", "text" => @transcript }
        @records << { "type" => "error", "error" => @error_code } if @error_code
      end
    end

    def read_nonblock
      @records.shift
    end

    def terminate
      @terminated = true
    end
  end

  test "uses fake Apple speech state and transcript records without audio" do
    process = FakeProcess.new
    service = EnglishArcadeVoiceCompanion::AppleSpeechService.new(
      platform: "test",
      process_factory: ->(_path) { process }
    )
    assert service.available?

    started = service.start(language: "en-US")
    capture_id = started.fetch("capture_id")
    assert_equal "listening", started.fetch("state")
    status = service.status_for(capture_id)
    assert_equal "I would verify the boundary.", status.fetch("transcript")
    assert_equal "listening", service.status.fetch("state")
    refute service.status.key?("transcript")

    stopped = service.stop(capture_id: capture_id)
    assert_equal "stopped", stopped.fetch("state")
    assert_equal "I would verify the boundary.", stopped.fetch("transcript")
    assert process.terminated
    assert_equal %w[start stop], process.writes.map { |write| write.fetch("type") }
    assert_raises(EnglishArcadeVoiceCompanion::AppleSpeechService::InvalidRequest) { service.status_for("bad") }
  end

  test "fails closed without macOS/helper and cleanup is idempotent" do
    service = EnglishArcadeVoiceCompanion::AppleSpeechService.new(platform: "linux")
    assert_not service.available?
    assert service.cleanup
    assert service.cleanup
  end

  test "keeps multibyte transcripts valid and below the NDJSON record budget" do
    process = FakeProcess.new
    process.transcript = "é" * 20_000
    service = EnglishArcadeVoiceCompanion::AppleSpeechService.new(
      platform: "test",
      process_factory: ->(_path) { process }
    )

    capture_id = service.start.fetch("capture_id")
    transcript = service.status_for(capture_id).fetch("transcript")
    assert_operator transcript.bytesize, :<=, EnglishArcadeVoiceCompanion::AppleSpeechService::MAX_TRANSCRIPT_BYTES
    assert transcript.valid_encoding?
  end

  test "preserves an allowlisted microphone permission error from the helper" do
    process = FakeProcess.new
    process.error_code = "microphone_permission_denied"
    service = EnglishArcadeVoiceCompanion::AppleSpeechService.new(
      platform: "test",
      process_factory: ->(_path) { process }
    )

    capture_id = service.start.fetch("capture_id")
    assert_equal "microphone_permission_denied", service.status_for(capture_id).fetch("error")
  end

  test "maps unknown helper errors to a generic speech error" do
    process = FakeProcess.new
    process.error_code = "unexpected_private_detail"
    service = EnglishArcadeVoiceCompanion::AppleSpeechService.new(
      platform: "test",
      process_factory: ->(_path) { process }
    )

    capture_id = service.start.fetch("capture_id")
    assert_equal "speech_unavailable", service.status_for(capture_id).fetch("error")
  end

  test "compile command is source-and-plist keyed and embeds the shipped plist" do
    source_file = Tempfile.new([ "english-arcade-helper", ".swift" ])
    source_file.write("print(\"helper-#{SecureRandom.hex(4)}\")")
    source_file.close
    source = source_file.path
    plist_file = Tempfile.new([ "english-arcade-helper", ".plist" ])
    plist_file.write("plist")
    plist_file.close
    plist = plist_file.path
    commands = []
    compiler = lambda do |command|
      commands << command
      output = command.fetch(command.index("-o") + 1)
      FileUtils.touch(output)
      [ "", "", Struct.new(:success?).new(true) ]
    end
    service = EnglishArcadeVoiceCompanion::AppleSpeechService.new(
      platform: "darwin-test",
      source_path: source,
      plist_path: plist,
      compiler: compiler
    )

    output = service.send(:compile_helper)
    command = commands.fetch(0)
    assert File.executable?(output)
    module_cache = command.fetch(command.index("-module-cache-path") + 1)
    assert_match(/\A#{Regexp.escape(Dir.tmpdir)}/, module_cache)
    refute File.exist?(module_cache)
    assert_includes command, "__TEXT"
    assert_includes command, "__info_plist"
    assert_includes command, plist
    assert_includes command, source
    assert_match(/\A#{Regexp.escape(Dir.tmpdir)}/, output)
  ensure
    FileUtils.rm_f(output) if output
    source_file&.unlink
    plist_file&.unlink
  end
end

# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "timeout"

module EnglishArcadeVoiceCompanion
  class AppleSpeechService
    DEFAULT_LANGUAGE = "en-US"
    MAX_RECORD_BYTES = 16 * 1024
    MAX_TRANSCRIPT_BYTES = 12 * 1024
    HELPER_ERROR_CODES = %w[
      speech_permission_denied
      microphone_permission_denied
      on_device_recognition_unavailable
      microphone_unavailable
      speech_capture_failed
      capture_timeout
    ].freeze

    class Unavailable < StandardError; end
    class InvalidRequest < StandardError; end

    attr_reader :helper_path

    def initialize(env: ENV, process_factory: nil, compiler: nil, platform: RUBY_PLATFORM, source_path: nil, plist_path: nil)
      @env = env
      @platform = platform
      @source_path = source_path || File.expand_path("../../native/english_arcade_voice_companion/AppleSpeechHelper.swift", __dir__)
      @plist_path = plist_path || File.expand_path("../../native/english_arcade_voice_companion/Info.plist", __dir__)
      @process_factory_injected = !process_factory.nil?
      @process_factory = process_factory || method(:default_process)
      @compiler = compiler
      @sessions = {}
      @mutex = Mutex.new
      @helper_path = env["ENGLISH_ARCADE_VOICE_COMPANION_HELPER"].to_s.strip
      @helper_path = nil if @helper_path.empty?
    end

    def available?
      return true if @process_factory_injected

      darwin? && (helper_binary_path || swift_available?)
    rescue StandardError
      false
    end

    def status
      @mutex.synchronize do
        drain_sessions
        {
          "available" => available?,
          "state" => if @sessions.empty? then "idle" else @sessions.values.any? { |session| session[:state] == "error" } ? "error" : "listening" end
        }
      end
    end

    def start(language: DEFAULT_LANGUAGE)
      value = language.to_s.strip
      value = DEFAULT_LANGUAGE if value.empty?
      raise InvalidRequest unless value.match?(/\A[a-z]{2}(?:-[A-Z]{2})?\z/)
      raise Unavailable unless available?

      @mutex.synchronize do
        cleanup_locked unless @sessions.empty?
        capture_id = SecureRandom.hex(16)
        executable = if @process_factory_injected
          @helper_path || @source_path
        else
          helper_binary_path || compile_helper
        end
        process = process_instance(executable)
        write(process, "type" => "start", "capture_id" => capture_id, "language" => value)
        @sessions[capture_id] = { process: process, state: "starting", transcript: "", error: nil }
        drain_session(@sessions.fetch(capture_id))
        { "capture_id" => capture_id, "state" => @sessions.fetch(capture_id).fetch(:state) }
      end
    rescue InvalidRequest, Unavailable
      raise
    rescue StandardError
      raise Unavailable
    end

    def status_for(capture_id)
      id = valid_id(capture_id)
      @mutex.synchronize do
        session = @sessions[id]
        return nil unless session

        drain_session(session)
        {
          "capture_id" => id,
          "state" => session.fetch(:state),
          "transcript" => session.fetch(:transcript),
          "error" => session[:error]
        }.compact
      end
    end

    def stop(capture_id:)
      id = valid_id(capture_id)
      @mutex.synchronize do
        session = @sessions.delete(id)
        return nil unless session

        drain_session(session)
        stop_session(session)
        { "capture_id" => id, "state" => "stopped", "transcript" => session.fetch(:transcript), "error" => session[:error] }.compact
      end
    end

    def cleanup
      @mutex.synchronize { cleanup_locked }
      true
    end

    private

    def darwin?
      @platform.to_s.include?("darwin")
    end

    def swift_available?
      return false unless File.file?(@source_path)

      system("which", "swiftc", out: File::NULL, err: File::NULL)
    end

    def helper_binary_path
      return @helper_path if @helper_path && File.executable?(@helper_path)
      return unless darwin? && File.file?(@source_path)

      digest = helper_digest
      path = File.join(Dir.tmpdir, "english-arcade-voice-helper-#{digest}")
      return path if File.executable?(path)

      nil
    end

    def compile_helper
      path = helper_binary_path
      return path if path
      raise Unavailable unless darwin? && (swift_available? || @compiler)

      digest = helper_digest
      output = File.join(Dir.tmpdir, "english-arcade-voice-helper-#{digest}")
      return output if File.executable?(output)

      temporary = "#{output}.#{Process.pid}.tmp"
      module_cache = Dir.mktmpdir("english-arcade-voice-module-", Dir.tmpdir)
      command = [
        "swiftc", "-O", "-module-cache-path", module_cache,
        "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", @plist_path,
        @source_path, "-o", temporary
      ]
      stdout, stderr, status = Timeout.timeout(30) { compile(command) }
      raise Unavailable unless status.success?

      FileUtils.chmod(0o700, temporary)
      FileUtils.mv(temporary, output)
      output
    rescue Timeout::Error, SystemCallError
      FileUtils.rm_f(temporary) if temporary
      raise Unavailable
    ensure
      FileUtils.remove_entry(module_cache) if module_cache && File.directory?(module_cache)
    end

    def helper_digest
      digest = Digest::SHA256.new
      digest << File.binread(@source_path)
      digest << "\0"
      digest << File.binread(@plist_path)
      digest.hexdigest[0, 24]
    end

    def compile(command)
      return @compiler.call(command) if @compiler

      Open3.capture3(*command)
    end

    def default_process(path)
      stdin, stdout, stderr, wait_thread = Open3.popen3(path)
      stderr_thread = Thread.new do
        stderr.each_line { |_line| } rescue nil
      end
      ProcessSession.new(stdin: stdin, stdout: stdout, wait_thread: wait_thread, stderr_thread: stderr_thread)
    end

    def write(process, payload)
      process.write(JSON.generate(payload) << "\n")
    end

    def process_instance(executable)
      arity = @process_factory.method(:call).arity
      arity.zero? ? @process_factory.call : @process_factory.call(executable)
    rescue NameError
      @process_factory.call(executable)
    end

    def valid_id(value)
      id = value.to_s
      raise InvalidRequest unless id.match?(/\A[0-9a-f]{32}\z/)

      id
    end

    def drain_sessions
      @sessions.each_value { |session| drain_session(session) }
    end

    def drain_session(session)
      while (record = session[:process].read_nonblock)
        next unless record.is_a?(Hash) && JSON.generate(record).bytesize <= MAX_RECORD_BYTES

        case record["type"].to_s
        when "state"
          state = record["state"].to_s
          session[:state] = state if %w[starting listening stopped].include?(state)
        when "transcript"
          text = bounded_utf8(record["text"], MAX_TRANSCRIPT_BYTES)
          session[:transcript] = text unless text.empty?
        when "error"
          session[:state] = "error"
          code = record["error"].to_s
          session[:error] = HELPER_ERROR_CODES.include?(code) ? code : "speech_unavailable"
        end
      end
    rescue IO::WaitReadable, EOFError
      nil
    rescue StandardError
      session[:state] = "error"
      session[:error] = "speech_unavailable"
    end

    def stop_session(session)
      write(session[:process], "type" => "stop") rescue nil
      session[:process].terminate rescue nil
    end

    def bounded_utf8(value, max_bytes)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").byteslice(0, max_bytes).to_s.force_encoding("UTF-8").scrub
    end

    def cleanup_locked
      @sessions.each_value { |session| stop_session(session) }
      @sessions.clear
      true
    end

    class ProcessSession
      def initialize(stdin:, stdout:, wait_thread:, stderr_thread:)
        @stdin = stdin
        @stdout = stdout
        @wait_thread = wait_thread
        @stderr_thread = stderr_thread
      end

      def write(value)
        @stdin.write(value)
        @stdin.flush
      end

      def read_nonblock
        ready = IO.select([ @stdout ], nil, nil, 0)
        return unless ready

        line = @stdout.gets
        return if line.nil?

        JSON.parse(line)
      end

      def terminate
        @stdin.close unless @stdin.closed?
        @stdout.close unless @stdout.closed?
        @wait_thread.join(1)
        return unless @wait_thread.alive?

        Process.kill("TERM", @wait_thread.pid) rescue nil
        @wait_thread.join(1)
      end
    end
  end
end

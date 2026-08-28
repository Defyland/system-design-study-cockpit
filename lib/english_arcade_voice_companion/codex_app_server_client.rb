# frozen_string_literal: true

require "json"
require "fileutils"
require "monitor"
require "open3"
require "securerandom"
require "tmpdir"
require "timeout"

module EnglishArcadeVoiceCompanion
  class CodexAppServerClient
    COMMAND = %w[codex app-server --listen stdio://].freeze
    MODEL = "gpt-5.6-luna"
    EFFORT = "max"
    APPROVAL_POLICY = "never"
    READ_ONLY_PERMISSION_PROFILE = ":read-only"
    INTERMEDIATE_ITEM_TYPES = %w[userMessage reasoning commandExecution].freeze
    DEFAULT_TIMEOUT_SECONDS = 30
    ANALYSIS_TIMEOUT_SECONDS = 90
    MAX_LINE_BYTES = 256 * 1024

    OUTPUT_FIELDS = %w[
      summary clarity fluency pace grammar relevance pronunciation limitations first_person_example
    ].freeze

    class Unavailable < StandardError; end
    class TimeoutError < Unavailable; end

    attr_reader :process_factory

    def initialize(process_factory: nil, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, analysis_timeout_seconds: ANALYSIS_TIMEOUT_SECONDS)
      @process_factory = process_factory || method(:default_process)
      @timeout_seconds = timeout_seconds
      @analysis_timeout_seconds = analysis_timeout_seconds
      @process = nil
      @next_id = 0
      @initialized = false
      @login_pending = false
      @mutex = Monitor.new
      @pending_messages = []
    end

    def status
      @mutex.synchronize do
        response = request("account/read", {}, timeout: @timeout_seconds)
        account = response["account"]
        return { "state" => "signed_in" } if account.is_a?(Hash) && account["type"] == "chatgpt"
        return { "state" => "signed_out" } if account.nil? && !@login_pending

        { "state" => @login_pending ? "login_pending" : "unavailable" }
      end
    rescue Unavailable
      terminate_process
      { "state" => "unavailable" }
    end

    def login_start
      @mutex.synchronize do
        response = request(
          "account/login/start",
          { "type" => "chatgpt", "useHostedLoginSuccessPage" => true, "appBrand" => "chatgpt" },
          timeout: @timeout_seconds
        )
        raise Unavailable unless response["type"] == "chatgpt" && response["authUrl"].is_a?(String)

        @login_pending = true
        { "state" => "login_pending", "authUrl" => response.fetch("authUrl") }
      end
    rescue Unavailable
      terminate_process
      raise
    rescue StandardError
      terminate_process
      raise Unavailable
    end

    def analyze(question:, answer:, context:, transcript:)
      @mutex.synchronize do
        prompt = Prompt.build(question: question, answer: answer, context: context, transcript: transcript)
        empty_cwd = Dir.mktmpdir("english-arcade-voice-")
        thread_id = nil
        turn_id = nil
        begin
          permission_profiles = request(
            "permissionProfile/list",
            { "cwd" => empty_cwd },
            timeout: @analysis_timeout_seconds
          )
          raise Unavailable unless permitted_read_only_profile?(permission_profiles)

          thread = request(
            "thread/start",
            {
              "ephemeral" => true,
              "cwd" => empty_cwd,
              "model" => MODEL,
              "approvalPolicy" => APPROVAL_POLICY,
              "permissions" => READ_ONLY_PERMISSION_PROFILE
            },
            timeout: @analysis_timeout_seconds
          )
          thread_id = extract_thread_id(thread)
          raise Unavailable unless thread_id

          turn = request(
            "turn/start",
            turn_params(thread_id: thread_id, cwd: empty_cwd, prompt: prompt),
            timeout: @analysis_timeout_seconds
          )
          turn_id = extract_turn_id(turn)
          raise Unavailable unless turn_id
          completed = await_completion(thread_id: thread_id, turn_id: turn_id, timeout: @analysis_timeout_seconds)
          parse_analysis(completed)
        rescue TimeoutError
          interrupt(thread_id: thread_id, turn_id: turn_id)
          terminate_process
          raise
        rescue StandardError => error
          interrupt(thread_id: thread_id, turn_id: turn_id) if thread_id
          terminate_process
          raise error if error.is_a?(Unavailable)

          raise Unavailable
        ensure
          # `thread/start` is ephemeral by contract and the official protocol
          # forbids deleting ephemeral roots. The temporary cwd is removed
          # after the turn; no transcript thread is reused.
          FileUtils.remove_entry(empty_cwd) if empty_cwd && File.directory?(empty_cwd)
        end
      end
    end

    def cleanup
      @mutex.synchronize do
        begin
          @process&.terminate
        ensure
          @process = nil
          @initialized = false
          @login_pending = false
          @pending_messages = []
          @last_message_from_pending = false
        end
      end
      true
    end

    private

    def default_process
      stdin, stdout, stderr, wait_thread = Open3.popen3(*COMMAND)
      stderr_thread = Thread.new { stderr.each_line { |_line| } rescue nil }
      ProcessSession.new(stdin: stdin, stdout: stdout, wait_thread: wait_thread, stderr_thread: stderr_thread)
    end

    def request(method, params, timeout:)
      ensure_initialized unless method == "initialize"
      id = next_id
      write_message("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params)
      deadline = monotonic + timeout.to_f
      loop do
        message = read_message(deadline)
        if message["id"].to_s == id.to_s
          raise Unavailable if message["error"]

          return message.fetch("result", {})
        end
        @pending_messages << message if message["method"] && !@last_message_from_pending
      end
    end

    def ensure_initialized
      return if @initialized

      id = next_id
      write_message(
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "initialize",
        "params" => {
          "clientInfo" => { "name" => "english_arcade_voice_companion", "title" => "English Arcade Voice Companion", "version" => VERSION },
          "capabilities" => { "experimentalApi" => true }
        }
      )
      deadline = monotonic + @timeout_seconds
      loop do
        message = read_message(deadline)
        if message["id"].to_s != id.to_s
          @pending_messages << message if message["method"] && !@last_message_from_pending
          next
        end

        raise Unavailable if message["error"]

        write_message("jsonrpc" => "2.0", "method" => "initialized")
        @initialized = true
        return
      end
    end

    def await_completion(thread_id:, turn_id:, timeout:)
      deadline = monotonic + timeout.to_f
      item = nil
      turn = nil
      loop do
        message = read_message(deadline)
        next unless message["method"]

        params = message["params"].is_a?(Hash) ? message["params"] : {}
        case message["method"]
        when "item/completed"
          next unless params["threadId"].to_s == thread_id.to_s
          next unless params["turnId"].to_s == turn_id.to_s
          candidate = params["item"]
          raise Unavailable unless candidate.is_a?(Hash)

          case candidate["type"]
          when "agentMessage"
            raise Unavailable if item

            item = candidate
          else
            raise Unavailable unless INTERMEDIATE_ITEM_TYPES.include?(candidate["type"])
          end
        when "turn/completed"
          next unless params["threadId"].to_s == thread_id.to_s
          next unless params.dig("turn", "id").to_s == turn_id.to_s
          candidate = params["turn"]
          raise Unavailable unless candidate.is_a?(Hash) && candidate["status"] == "completed"

          turn = candidate
        end
        return { "item" => item, "turn" => turn } if item && turn
      end
    end

    def turn_params(thread_id:, cwd:, prompt:)
      {
        "threadId" => thread_id,
        "cwd" => cwd,
        "model" => MODEL,
        "effort" => EFFORT,
        "approvalPolicy" => APPROVAL_POLICY,
        "input" => [ { "type" => "text", "text" => prompt } ],
        "outputSchema" => output_schema
      }
    end

    def permitted_read_only_profile?(response)
      profiles = response.is_a?(Hash) ? response["data"] : nil
      profiles.is_a?(Array) && profiles.any? do |profile|
        profile.is_a?(Hash) && profile["id"] == READ_ONLY_PERMISSION_PROFILE && profile["allowed"] == true
      end
    end

    def output_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => OUTPUT_FIELDS,
        "properties" => OUTPUT_FIELDS.to_h { |field| [ field, { "type" => "string" } ] }
      }
    end

    def parse_analysis(completed)
      text = extract_text(completed["item"]).strip
      text = text.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
      parsed = JSON.parse(text)
      raise Unavailable unless parsed.is_a?(Hash) && OUTPUT_FIELDS.all? { |field| parsed[field].is_a?(String) }

      OUTPUT_FIELDS.to_h { |field| [ field, parsed.fetch(field).strip ] }
    rescue JSON::ParserError, TypeError
      raise Unavailable
    end

    def extract_text(item)
      return "" unless item.is_a?(Hash)
      return item["text"].to_s if item["text"].is_a?(String)

      content = item["content"]
      if content.is_a?(Array)
        return content.filter_map do |part|
          next unless part.is_a?(Hash)

          part["text"] || part.dig("content", "text")
        end.join
      end

      item.values.filter_map { |value| extract_text(value) if value.is_a?(Hash) || value.is_a?(Array) }.join
    end

    def extract_thread_id(response)
      values = [ response.dig("thread", "id"), response["threadId"], response["id"] ]
      values.map { |value| value.to_s }.find { |value| !value.empty? }
    end

    def extract_turn_id(response)
      values = [ response.dig("turn", "id"), response["turnId"], response["id"] ]
      values.map { |value| value.to_s }.find { |value| !value.empty? }
    end

    def interrupt(thread_id:, turn_id:)
      return unless thread_id && turn_id

      request("turn/interrupt", { "threadId" => thread_id, "turnId" => turn_id }, timeout: 5)
    rescue StandardError
      nil
    end

    def read_message(deadline)
      remaining = deadline - monotonic
      raise TimeoutError if remaining <= 0

      @last_message_from_pending = !@pending_messages.empty?
      line = if @pending_messages.empty?
        @process.read_line(timeout: remaining)
      else
        @pending_messages.shift
      end
      return line if line.is_a?(Hash)
      raise Unavailable if line.nil? || line.bytesize > MAX_LINE_BYTES

      JSON.parse(line)
    rescue JSON::ParserError
      retry
    rescue Timeout::Error, IO::WaitReadable
      raise TimeoutError
    end

    def write_message(payload)
      @process ||= process_instance
      @process.write(JSON.generate(payload) << "\n")
    rescue StandardError
      raise Unavailable
    end

    def next_id
      @next_id += 1
    end

    def process_instance
      arity = @process_factory.arity if @process_factory.respond_to?(:arity)
      arity == 0 ? @process_factory.call : @process_factory.call(COMMAND)
    rescue NameError
      @process_factory.call(COMMAND)
    end

    def terminate_process
      @process&.terminate
      @process = nil
      @initialized = false
      @pending_messages = []
      @login_pending = false
      @last_message_from_pending = false
    rescue StandardError
      @process = nil
      @initialized = false
      @pending_messages = []
      @login_pending = false
      @last_message_from_pending = false
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

      def read_line(timeout:)
        ready = IO.select([ @stdout ], nil, nil, timeout)
        raise Timeout::Error unless ready

        @stdout.gets
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

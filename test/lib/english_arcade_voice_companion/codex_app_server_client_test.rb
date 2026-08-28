require "test_helper"
require "english_arcade_voice_companion"

class EnglishArcadeVoiceCompanionCodexAppServerClientTest < ActiveSupport::TestCase
  class FakeProcess
    attr_reader :writes
    attr_accessor :account, :permission_profiles, :timeout_turn, :terminated, :completion_item_type, :completion_status

    def initialize
      @writes = []
      @queue = []
      @account = nil
      @permission_profiles = [ { "id" => ":read-only", "allowed" => true } ]
      @timeout_turn = false
      @terminated = false
      @completion_item_type = "agentMessage"
      @completion_status = "completed"
    end

    def write(value)
      message = JSON.parse(value)
      @writes << message
      case message["method"]
      when "initialize"
        enqueue("jsonrpc" => "2.0", "id" => message["id"], "result" => {})
      when "account/read"
        enqueue("jsonrpc" => "2.0", "id" => message["id"], "result" => { "account" => @account, "requiresOpenaiAuth" => true })
      when "permissionProfile/list"
        enqueue("jsonrpc" => "2.0", "id" => message["id"], "result" => { "data" => @permission_profiles })
      when "account/login/start"
        @account = { "type" => "chatgpt", "email" => "hidden@example.test", "planType" => "plus" }
        enqueue("jsonrpc" => "2.0", "id" => message["id"], "result" => { "type" => "chatgpt", "authUrl" => "https://auth.example.test/managed", "loginId" => "hidden-login" })
      when "thread/start"
        enqueue("jsonrpc" => "2.0", "id" => message["id"], "result" => { "thread" => { "id" => "thread-1" } })
      when "turn/start"
        enqueue("jsonrpc" => "2.0", "id" => message["id"], "result" => { "turn" => { "id" => "turn-1" } })
        unless @timeout_turn
          output = EnglishArcadeVoiceCompanion::CodexAppServerClient::OUTPUT_FIELDS.to_h { |field| [ field, "safe #{field}" ] }
          %w[userMessage reasoning commandExecution commandExecution commandExecution reasoning].each do |item_type|
            enqueue(
              "jsonrpc" => "2.0",
              "method" => "item/completed",
              "params" => {
                "threadId" => "thread-1",
                "turnId" => "turn-1",
                "item" => { "type" => item_type }
              }
            )
          end
          enqueue(
            "jsonrpc" => "2.0",
            "method" => "item/completed",
            "params" => {
              "threadId" => "thread-1",
              "turnId" => "turn-1",
              "item" => { "type" => @completion_item_type, "content" => [ { "type" => "text", "text" => JSON.generate(output) } ] }
            }
          )
          enqueue(
            "jsonrpc" => "2.0",
            "method" => "turn/completed",
            "params" => { "threadId" => "thread-1", "turn" => { "id" => "turn-1", "status" => @completion_status } }
          )
        end
      when "turn/interrupt"
        enqueue("jsonrpc" => "2.0", "id" => message["id"], "result" => {})
      end
    end

    def read_line(timeout:)
      raise Timeout::Error if @queue.empty?

      @queue.shift
    end

    def terminate
      @terminated = true
    end

    private

    def enqueue(message)
      @queue << JSON.generate(message)
    end
  end

  setup do
    @process = FakeProcess.new
    @client = EnglishArcadeVoiceCompanion::CodexAppServerClient.new(
      process_factory: ->(command) {
        assert_equal %w[codex app-server --listen stdio://], command
        @process
      },
      timeout_seconds: 1,
      analysis_timeout_seconds: 1
    )
  end

  test "initializes once, uses managed ChatGPT account methods, and hides identity" do
    assert_equal "signed_out", @client.status.fetch("state")
    login = @client.login_start
    assert_equal "login_pending", login.fetch("state")
    assert_equal "https://auth.example.test/managed", login.fetch("authUrl")
    assert_equal "signed_in", @client.status.fetch("state")

    methods = @process.writes.filter_map { |write| write["method"] }
    assert_equal 1, methods.count("initialize")
    assert_equal 1, methods.count("initialized")
    assert_equal 2, methods.count("account/read")
    assert_equal 1, methods.count("account/login/start")
    login_request = @process.writes.find { |write| write["method"] == "account/login/start" }
    assert_equal({ "type" => "chatgpt", "useHostedLoginSuccessPage" => true, "appBrand" => "chatgpt" }, login_request.fetch("params"))
    initialize_request = @process.writes.find { |write| write["method"] == "initialize" }
    assert_equal true, initialize_request.dig("params", "capabilities", "experimentalApi")
    refute @process.writes.any? { |write| write["method"].to_s.include?("oauth") }
    refute @process.writes.any? { |write| write.to_s.include?("auth.json") }
  end

  test "supports zero-arity process factories for managed account status" do
    process = FakeProcess.new
    client = EnglishArcadeVoiceCompanion::CodexAppServerClient.new(
      process_factory: -> { process },
      timeout_seconds: 1
    )

    assert_equal "signed_out", client.status.fetch("state")
    process.account = { "type" => "chatgpt" }
    assert_equal "signed_in", client.status.fetch("state")
  end

  test "uses the ninety-second analysis default while allowing injected test bounds" do
    assert_equal 90, EnglishArcadeVoiceCompanion::CodexAppServerClient::ANALYSIS_TIMEOUT_SECONDS
    default_client = EnglishArcadeVoiceCompanion::CodexAppServerClient.new(
      process_factory: ->(_command) { @process }
    )
    assert_equal 90, default_client.instance_variable_get(:@analysis_timeout_seconds)

    configured = EnglishArcadeVoiceCompanion::CodexAppServerClient.new(
      process_factory: ->(_command) { @process },
      analysis_timeout_seconds: 7
    )
    assert_equal 7, configured.instance_variable_get(:@analysis_timeout_seconds)
  end

  test "uses fresh ephemeral Luna threads and consumes both authoritative completion events" do
    result = @client.analyze(
      question: "How do you protect a boundary?",
      answer: "I would verify it before changing it.",
      context: "Visible authored context",
      transcript: "I would verify it."
    )
    assert_equal "safe summary", result.fetch("summary")

    thread_start = @process.writes.find { |write| write["method"] == "thread/start" }
    assert_equal true, thread_start.dig("params", "ephemeral")
    assert_equal "gpt-5.6-luna", thread_start.dig("params", "model")
    assert_equal "never", thread_start.dig("params", "approvalPolicy")
    assert_equal ":read-only", thread_start.dig("params", "permissions")
    refute thread_start.fetch("params").key?("sandbox")
    refute thread_start.fetch("params").key?("sandboxPolicy")
    cwd = thread_start.dig("params", "cwd")
    refute File.directory?(cwd)

    permission_list = @process.writes.find { |write| write["method"] == "permissionProfile/list" }
    assert_equal cwd, permission_list.dig("params", "cwd")
    assert_operator @process.writes.index(permission_list), :<, @process.writes.index(thread_start)

    turn_start = @process.writes.find { |write| write["method"] == "turn/start" }
    assert_equal "gpt-5.6-luna", turn_start.dig("params", "model")
    assert_equal "max", turn_start.dig("params", "effort")
    assert_equal "never", turn_start.dig("params", "approvalPolicy")
    refute turn_start.fetch("params").key?("sandboxPolicy")
    refute turn_start.fetch("params").key?("permissions")
    assert_equal EnglishArcadeVoiceCompanion::CodexAppServerClient::OUTPUT_FIELDS.sort, turn_start.dig("params", "outputSchema", "required").sort
    prompt = turn_start.dig("params", "input", 0, "text")
    assert_includes prompt, "No tools, files, or network are needed"
    assert_includes prompt, "Visible authored context"
    refute @process.writes.any? { |write| write["method"] == "thread/delete" }
  end

  test "fails closed when the exact read-only permission profile is unavailable" do
    [
      [ { "id" => ":workspace-write", "allowed" => true } ],
      [ { "id" => ":read-only", "allowed" => false } ]
    ].each do |profiles|
      process = FakeProcess.new
      process.permission_profiles = profiles
      client = EnglishArcadeVoiceCompanion::CodexAppServerClient.new(
        process_factory: ->(_command) { process },
        timeout_seconds: 1,
        analysis_timeout_seconds: 1
      )

      assert_raises(EnglishArcadeVoiceCompanion::CodexAppServerClient::Unavailable) do
        client.analyze(question: "Question", answer: "Answer", context: "", transcript: "Transcript")
      end
      assert process.terminated
      assert process.writes.any? { |write| write["method"] == "permissionProfile/list" }
      refute process.writes.any? { |write| write["method"] == "thread/start" }
    end
  end

  test "interrupts and terminates the app-server process on an analysis timeout" do
    @process.timeout_turn = true
    client = EnglishArcadeVoiceCompanion::CodexAppServerClient.new(
      process_factory: ->(_command) { @process },
      timeout_seconds: 1,
      analysis_timeout_seconds: 0.01
    )
    assert_raises(EnglishArcadeVoiceCompanion::CodexAppServerClient::TimeoutError) do
      client.analyze(question: "Question", answer: "Answer", context: "", transcript: "Transcript")
    end
    assert @process.writes.any? { |write| write["method"] == "turn/interrupt" }
    assert @process.terminated
  end

  test "consumes normal intermediate items and fails closed for unexpected completion items" do
    %w[fileChange dynamicToolCall failed].each do |item_type|
      process = FakeProcess.new
      process.completion_item_type = item_type
      client = EnglishArcadeVoiceCompanion::CodexAppServerClient.new(
        process_factory: ->(_command) { process },
        timeout_seconds: 1,
        analysis_timeout_seconds: 1
      )

      assert_raises(EnglishArcadeVoiceCompanion::CodexAppServerClient::Unavailable) do
        client.analyze(question: "Question", answer: "Answer", context: "", transcript: "Transcript")
      end
      assert process.terminated
    end
  end

  test "fails closed when the matching turn completes with a failure status" do
    @process.completion_status = "failed"
    assert_raises(EnglishArcadeVoiceCompanion::CodexAppServerClient::Unavailable) do
      @client.analyze(question: "Question", answer: "Answer", context: "", transcript: "Transcript")
    end
    assert @process.terminated
  end

  test "does not treat API-key accounts as managed ChatGPT sign-in" do
    @process.account = { "type" => "apiKey", "email" => "hidden@example.test" }
    status = @client.status
    assert_equal "unavailable", status.fetch("state")
    refute status.key?("email")
    refute status.key?("token")
  end

  test "cleanup is idempotent and resets account state" do
    @process.account = { "type" => "chatgpt" }
    assert_equal "signed_in", @client.status.fetch("state")
    assert @client.cleanup
    assert @client.cleanup
    assert_nil @client.instance_variable_get(:@process)
    assert_equal false, @client.instance_variable_get(:@login_pending)
    assert_empty @client.instance_variable_get(:@pending_messages)
  end
end

require "application_system_test_case"

class EnglishArcadeVoiceTest < ApplicationSystemTestCase
  FakeReservation = Struct.new(:released)

  class FakeBudget
    attr_reader :reservations

    def initialize(reservation: FakeReservation.new(false))
      @reservation = reservation
      @reservations = []
    end

    def reserve(**)
      return unless @reservation

      @reservations << @reservation
      @reservation
    end

    def release(reservation)
      reservation.released = true if reservation
      true
    end
  end

  class FakeClient
    attr_accessor :failure
    attr_reader :calls

    def initialize(failure: false)
      @failure = failure
      @calls = []
    end

    def create_call(**arguments)
      @calls << arguments
      raise EnglishArcadeVoice::RealtimeCallsClient::UpstreamError.new(status: 503) if failure

      "v=0\r\nfake-answer\r\n"
    end
  end

  setup do
    Capybara.reset_sessions!
    @saved_environment = %w[
      ENGLISH_ARCADE_VOICE_ENABLED OPENAI_API_KEY STUDY_COCKPIT_USERNAME STUDY_COCKPIT_PASSWORD
    ].to_h { |key| [ key, ENV[key] ] }
    @assets = Rails.application.assets
    @saved_manifest_path = @assets.config.manifest_path
    @assets.config.manifest_path = Pathname("/private/tmp/system-design-study-cockpit-voice-test-manifest-#{Process.pid}.json")
    @assets.instance_variable_set(:@resolver, nil)
    ENV.delete("ENGLISH_ARCADE_VOICE_ENABLED")
    ENV.delete("OPENAI_API_KEY")
    EnglishArcadeAttempt.delete_all
    EnglishArcadeCard.delete_all
    EnglishArcadeSession.delete_all
    @budget = FakeBudget.new
    @client = FakeClient.new
    @voice_controller = EnglishArcadeVoiceCallsController
    @previous_budget_factory = @voice_controller.voice_budget_factory
    @previous_client_factory = @voice_controller.voice_client_factory
    @voice_controller.voice_budget_factory = ->(_configuration) { @budget }
    @voice_controller.voice_client_factory = ->(_configuration) { @client }
  end

  teardown do
    @voice_controller.voice_budget_factory = @previous_budget_factory
    @voice_controller.voice_client_factory = @previous_client_factory
    @assets.config.manifest_path = @saved_manifest_path
    @assets.instance_variable_set(:@resolver, nil)
    @saved_environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "Guided starts with Apple Speech and Codex when Realtime is not configured" do
    visit "/english-arcade"
    page.execute_script("window.localStorage.clear(); window.sessionStorage.clear()")
    find("label[for='english-arcade-target-career']").click
    click_button "Start guided study"

    assert_selector ".guided-experience"
    assert_selector ".english-arcade-voice", minimum: 1
    assert_equal "apple_codex", find(
      ".english-arcade-voice [data-english-arcade-voice-target='provider']",
      match: :first
    ).value
    assert_text "Apple Speech + Codex"
    refute_includes page.html, "sk-system-test-only"
  end

  test "Apple local reading speaks exact card text without pairing or Realtime" do
    start_guided
    install_local_speech_fake

    question = voice_attribute("question")
    answer = voice_attribute("answer")
    click_voice_target("enable")

    assert_text(/Local Apple Speech reading is enabled/i)
    assert_equal 0, page.evaluate_script("window.__voiceLocalFake.companionFetches")
    refute voice_target("listenQuestion").disabled?
    refute voice_target("listenAnswer").disabled?
    assert_text(/My answer to practise aloud/i)

    click_voice_target("listenQuestion")
    click_voice_target("listenAnswer")
    assert_equal [ question, answer ], page.evaluate_script("window.__voiceLocalFake.spoken")
    assert_operator page.evaluate_script("window.__voiceLocalFake.cancelCalls"), :>=, 2
    assert_equal answer, page.evaluate_script("window.__voiceLocalFake.active.text")

    click_voice_target("stopSpeaking")
    assert_text(/Local speech stopped/i)
    assert_operator page.evaluate_script("window.__voiceLocalFake.cancelCalls"), :>=, 3
    click_voice_target("end")
    assert_text(/Voice ended and cleaned up/i)
  end

  test "Apple lifecycle cleanup cancels speech and companion capture idempotently" do
    start_guided
    install_local_speech_fake
    install_companion_fake
    fill_pairing_secret("pairing-secret-lifecycle")
    click_voice_target("pair")
    assert_text(/Apple companion connected/i)

    click_voice_target("enable")
    assert_text(/Local Apple Speech reading is enabled/i)
    click_voice_target("listenQuestion")
    assert_text(/Reading the exact authored question locally/i)
    click_voice_target("startMicrophone")
    assert_text(/Apple Speech listening/i)

    cancel_before = page.evaluate_script("window.__voiceLocalFake.cancelCalls")
    cleanup_before = page.evaluate_script("window.__voiceCompanionFake.cleanupCalls")
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")

    assert_operator page.evaluate_script("window.__voiceCompanionFake.cleanupCalls"), :>=, cleanup_before + 1
    assert_operator page.evaluate_script("window.__voiceLocalFake.cancelCalls"), :>, cancel_before
    assert_browser_script <<~JAVASCRIPT
      (() => {
        const root = document.querySelector('.english-arcade-voice')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'english-arcade-voice')
        return controller.appleCaptureId === null && controller.applePollTimer === null &&
          controller.durationTimer === null && controller.localEnabled === false &&
          controller.companionConnected === false && controller.speaking === false
      })()
    JAVASCRIPT

    cleanup_after = page.evaluate_script("window.__voiceCompanionFake.cleanupCalls")
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_equal cleanup_after, page.evaluate_script("window.__voiceCompanionFake.cleanupCalls")
  end

  test "Apple companion pairs, signs in, captures, analyzes, and cleans up" do
    start_guided
    install_companion_fake
    secret = "pairing-secret-happy-path"
    refute_includes page.html, secret

    fill_pairing_secret(secret)
    click_voice_target("pair")
    assert_text(/Apple companion connected/i)
    assert_equal secret, page.evaluate_script("window.sessionStorage.getItem('english_arcade_voice_pairing')")
    assert_nil page.evaluate_script("window.localStorage.getItem('english_arcade_voice_pairing')")
    refute page.evaluate_script("Object.values(window.localStorage).includes('pairing-secret-happy-path')")
    assert_browser_script "window.__voiceCompanionFake.requests.some((request) => request.headers['X-English-Arcade-Pairing'] === 'pairing-secret-happy-path')"
    assert_browser_script "window.__voiceCompanionFake.requests.every((request) => !request.url.includes('pairing-secret-happy-path') && !request.body.includes('pairing-secret-happy-path'))"
    assert_text(/Codex: signed out/i)
    refute_match(/(?:@example|access_token|account_id)/i, page.html)

    click_voice_target("login")
    assert_text(/Managed login opened/i)
    assert_browser_script "window.__voiceCompanionFake.codexState === 'login_pending'"
    assert_browser_script "window.__voiceCompanionFake.popup.location.href === 'https://chatgpt.com/auth/managed-test' && window.__voiceCompanionFake.popup.opener === null"
    refute_match(/(?:@example|access_token|account_id)/i, page.html)

    page.execute_script("window.__voiceCompanionFake.codexState = 'signed_in'")
    click_voice_target("refreshStatus")
    assert_text(/Codex: signed in/i)

    click_voice_target("startMicrophone")
    assert_text(/Apple Speech listening/i)
    run_next_companion_poll
    assert_text(/You: I would verify the invariant/i)
    click_voice_target("stopMicrophone")
    assert_text(/Codex feedback received/i)
    %w[Summary Clarity Fluency Pace Grammar Relevance Pronunciation Limitations Safe\ first-person\ example].each do |label|
      assert_text label
    end
    assert_browser_script "window.__voiceCompanionFake.analyzeCalls === 1"

    click_voice_target("end")
    assert_text(/Voice ended and cleaned up/i)
    assert_browser_script "window.__voiceCompanionFake.cleanupCalls === 1"
  end

  test "Apple companion failures stay explicit and do not fall back to Realtime" do
    start_guided
    install_companion_fake
    secret = "pairing-secret-negative-path"
    fill_pairing_secret(secret)

    page.execute_script("window.__voiceCompanionFake.pairRejected = true")
    click_voice_target("pair")
    assert_text(/pairing secret was rejected/i)
    assert_equal "apple_codex", provider_value
    assert_browser_script "window.__voiceCompanionFake.railsFetches.length === 0"

    page.execute_script("window.__voiceCompanionFake.pairRejected = false; window.__voiceCompanionFake.failNetwork = true")
    click_voice_target("pair")
    assert_text(/could not be reached|unavailable/i)
    assert_equal "apple_codex", provider_value
    assert_browser_script "window.__voiceCompanionFake.railsFetches.length === 0"

    page.execute_script("window.__voiceCompanionFake.failNetwork = false; window.__voiceCompanionFake.timeoutCompanion = true")
    click_voice_target("pair")
    assert_browser_script "window.__voiceCompanionFake.timeoutCallbacks.length === 1"
    page.execute_script("const callback = window.__voiceCompanionFake.timeoutCallbacks.shift(); callback && callback()")
    assert_text(/timed out/i)
    assert_equal "apple_codex", provider_value
    assert_browser_script "window.__voiceCompanionFake.railsFetches.length === 0"

    page.execute_script("window.__voiceCompanionFake.timeoutCompanion = false; window.__voiceCompanionFake.speechError = 'microphone_permission_denied'")
    click_voice_target("pair")
    assert_text(/Apple companion connected/i)
    click_voice_target("startMicrophone")
    assert_text(/Apple Speech listening/i)
    run_next_companion_poll
    assert_text(/Microphone permission was denied/i)
    assert_equal "apple_codex", provider_value
    assert_browser_script "window.__voiceCompanionFake.analyzeCalls === 0"
    assert_equal "", voice_target("transcript").text
  end

  test "Realtime stays explicit, records selected models, and deduplicates temporary transcript" do
    ENV["ENGLISH_ARCADE_VOICE_ENABLED"] = "true"
    ENV["OPENAI_API_KEY"] = "sk-system-test-only"
    start_guided
    install_realtime_fake
    choose_provider("openai_realtime")

    assert_text(/Platform billing/i)
    assert_equal "openai_realtime", page.evaluate_script("window.localStorage.getItem('english_arcade_voice_provider')")
    assert_browser_script "Array.from(document.querySelectorAll('[data-english-arcade-voice-target=provider]')).every((select) => select.value === 'openai_realtime')"
    assert_equal "gpt-realtime-2.1-mini", voice_target("model").value

    click_voice_target("enable")
    assert_text(/OpenAI Realtime connected/i)
    assert_equal "gpt-realtime-2.1-mini", @client.calls.last.fetch(:model)
    assert_browser_script "window.__voiceRealtimeFake.channels[0].readyState === 'open'"
    click_voice_target("listenQuestion")
    assert_text(/Requesting temporary OpenAI Realtime audio/i)
    sent_payloads = page.evaluate_script("window.__voiceRealtimeFake.channels[0].sent")
    assert_equal 1, sent_payloads.length
    click_voice_target("listenAnswer")
    sent_payloads = page.evaluate_script("window.__voiceRealtimeFake.channels[0].sent")
    assert_equal 2, sent_payloads.length
    assert sent_payloads.all? { |payload| JSON.parse(payload).fetch("type") == "response.create" }

    emit_realtime_event(type: "conversation.item.input_audio_transcription.delta", item_id: "input-1", delta: "hello ")
    emit_realtime_event(type: "conversation.item.input_audio_transcription.completed", item_id: "input-1", transcript: "hello world")
    assert_text "You: hello world"
    assert_browser_script "document.querySelectorAll('.voice-transcript p').length === 1"

    page.execute_script("window.__voiceRealtimeFake.micDenied = true")
    click_voice_target("startMicrophone")
    assert_text(/Microphone access was denied/i)

    click_voice_target("end")
    assert_text(/Voice ended and cleaned up/i)
    assert_browser_script "window.__voiceRealtimeFake.peers[0].closed === true && window.__voiceRealtimeFake.channels[0].readyState === 'closed'"

    choose_model("gpt-realtime-2.1")
    click_voice_target("enable")
    assert_text(/OpenAI Realtime connected/i)
    assert_equal "gpt-realtime-2.1", @client.calls.last.fetch(:model)
    click_voice_target("end")
  end

  test "Realtime is unavailable without configuration and cleans up a failed or timed-out call" do
    start_guided
    install_realtime_fake
    choose_provider("openai_realtime")
    assert voice_target("enable").disabled?
    assert_text(/OpenAI Realtime is unavailable/i)
    choose_provider("apple_codex")
    refute voice_target("enable").disabled?
    assert_browser_script "window.__voiceRealtimeFake.peers.length === 0"

    ENV["ENGLISH_ARCADE_VOICE_ENABLED"] = "true"
    ENV["OPENAI_API_KEY"] = "sk-system-test-only"
    start_guided
    install_realtime_fake
    choose_provider("openai_realtime")
    @client.failure = true
    click_voice_target("enable")
    assert_text(/OpenAI Realtime is unavailable|setup failed/i)
    assert_equal "openai_realtime", provider_value
    assert_browser_script "window.__voiceRealtimeFake.peers.every((peer) => peer.closed)"

    @client.failure = false
    page.execute_script("window.__voiceRealtimeFake.clock = 1; window.__voiceRealtimeFake.captureDurationTimer = true")
    click_voice_target("enable")
    assert_text(/OpenAI Realtime connected/i)
    assert_browser_script "window.__voiceRealtimeFake.durationCallback !== null"
    page.execute_script("window.__voiceRealtimeFake.clock = 600001; window.__voiceRealtimeFake.durationCallback()")
    assert_text(/ten-minute.*cleaned up/i)
    assert_browser_script "window.__voiceRealtimeFake.peers.at(-1).closed === true"
    refute_includes page.html, "sk-system-test-only"
  end

  private

  def start_guided
    visit "/english-arcade"
    page.execute_script("window.localStorage.clear(); window.sessionStorage.clear()")
    find("label[for='english-arcade-target-career']").click
    assert_selector("#english-arcade-target-career:checked")
    click_button "Start guided study"
    assert_current_path(/\/english_arcade\?session_id=/)
    assert_selector ".guided-experience"
    assert_selector ".english-arcade-voice", minimum: 1
  end

  def voice_target(name)
    find(".english-arcade-voice [data-english-arcade-voice-target='#{name}']", match: :first)
  end

  def click_voice_target(name)
    voice_target(name).click
  end

  def provider_value
    voice_target("provider").value
  end

  def choose_provider(value)
    raise ArgumentError unless %w[apple_codex openai_realtime].include?(value)

    page.execute_script("const select = document.querySelector('.english-arcade-voice [data-english-arcade-voice-target=provider]'); select.value = '#{value}'; select.dispatchEvent(new Event('change', { bubbles: true }));")
    assert_equal value, provider_value
  end

  def choose_model(value)
    page.execute_script("const select = document.querySelector('.english-arcade-voice [data-english-arcade-voice-target=model]'); select.value = '#{value}'; select.dispatchEvent(new Event('change', { bubbles: true }));")
    assert_equal value, voice_target("model").value
  end

  def emit_realtime_event(payload)
    page.execute_script("window.__voiceRealtimeFake.channels.at(-1).emit(#{JSON.generate(payload)})")
  end

  def voice_attribute(name)
    page.evaluate_script("document.querySelector('.english-arcade-voice').getAttribute('data-english-arcade-voice-#{name}-value')")
  end

  def fill_pairing_secret(secret)
    voice_target("pairingSecret").set(secret)
  end

  def run_next_companion_poll
    assert_browser_script "window.__voiceCompanionFake.pollCallbacks.length > 0"
    page.execute_script("const callback = window.__voiceCompanionFake.pollCallbacks.shift(); callback && callback()")
  end

  def assert_browser_script(script)
    assert page.evaluate_script(script), "Expected browser expression to be truthy: #{script}"
  end

  def install_local_speech_fake
    page.execute_script(<<~'JAVASCRIPT')
      (() => {
        const fake = window.__voiceLocalFake = { companionFetches: 0, spoken: [], cancelCalls: 0, active: null }
        const originalFetch = window.fetch.bind(window)
        window.fetch = (input, init = {}) => {
          const url = typeof input === "string" ? input : input.url
          if (url.startsWith("http://127.0.0.1:43129")) {
            fake.companionFetches += 1
            return Promise.reject(new TypeError("local companion must not be called for reading"))
          }
          return originalFetch(input, init)
        }

        class FakeUtterance {
          constructor(text) {
            this.text = text
            this.lang = ""
            this.onstart = null
            this.onend = null
            this.onerror = null
          }
        }
        Object.defineProperty(window, "SpeechSynthesisUtterance", {
          configurable: true,
          writable: true,
          value: FakeUtterance
        })
        Object.defineProperty(window, "speechSynthesis", {
          configurable: true,
          value: {
            speak(utterance) {
              fake.spoken.push(utterance.text)
              fake.active = utterance
              utterance.onstart?.()
            },
            cancel() {
              fake.cancelCalls += 1
              fake.active = null
            }
          }
        })
      })()
    JAVASCRIPT
  end

  def install_companion_fake
    page.execute_script(<<~'JAVASCRIPT')
      (() => {
        const fake = window.__voiceCompanionFake = {
          codexState: "signed_out",
          requests: [],
          railsFetches: [],
          pollCallbacks: [],
          timeoutCallbacks: [],
          analyzeCalls: 0,
          cleanupCalls: 0,
          loginCalls: 0,
          pairRejected: false,
          failNetwork: false,
          timeoutCompanion: false,
          speechError: null,
          speechStatusCalls: 0,
          captureId: "capture-happy-path",
          transcript: "I would verify the invariant before changing the implementation.",
          popup: { closed: false, opener: null, location: { href: "" }, close() { this.closed = true } }
        }
        const originalFetch = window.fetch.bind(window)
        const originalSetTimeout = window.setTimeout.bind(window)
        const originalClearTimeout = window.clearTimeout.bind(window)
        window.setTimeout = (callback, delay, ...args) => {
          if (delay === 500) {
            fake.pollCallbacks.push(() => callback(...args))
            return `companion-poll-${fake.pollCallbacks.length}`
          }
          if (delay === 10_000 && fake.timeoutCompanion) {
            fake.timeoutCallbacks.push(() => callback(...args))
            return `companion-timeout-${fake.timeoutCallbacks.length}`
          }
          return originalSetTimeout(callback, delay, ...args)
        }
        window.clearTimeout = (identifier) => {
          if (typeof identifier === "string" && identifier.startsWith("companion-poll-")) return
          if (typeof identifier === "string" && identifier.startsWith("companion-timeout-")) return
          originalClearTimeout(identifier)
        }
        const response = (body, status = 200) => new Response(JSON.stringify(body), {
          status,
          headers: { "Content-Type": "application/json" }
        })
        window.open = (_url, _target, _features) => fake.popup
        window.fetch = (input, init = {}) => {
          const url = typeof input === "string" ? input : input.url
          if (!url.startsWith("http://127.0.0.1:43129")) {
            fake.railsFetches.push({ url, method: init.method || "GET", body: init.body || "" })
            return originalFetch(input, init)
          }
          const rawHeaders = init.headers || {}
          const headers = typeof rawHeaders.get === "function"
            ? Object.fromEntries(rawHeaders.entries())
            : { ...rawHeaders }
          const request = { url, method: init.method || "GET", headers, body: init.body || "" }
          fake.requests.push(request)
          const path = new URL(url).pathname
          if (fake.failNetwork) return Promise.reject(new TypeError("companion network"))
          if (fake.timeoutCompanion) {
            return new Promise((_resolve, reject) => {
              const abort = () => {
                const error = new Error("timeout")
                error.name = "AbortError"
                reject(error)
              }
              if (init.signal?.aborted) abort()
              else init.signal?.addEventListener("abort", abort, { once: true })
            })
          }
          if (fake.pairRejected) return Promise.resolve(response({ error: "pairing_required" }, 401))
          if (path === "/v1/status") {
            return Promise.resolve(response({
              companion: "ready",
              apple: { available: true, state: "idle" },
              codex: { state: fake.codexState }
            }))
          }
          if (path === "/v1/login") {
            fake.loginCalls += 1
            fake.codexState = "login_pending"
            return Promise.resolve(response({ state: "login_pending", authUrl: "https://chatgpt.com/auth/managed-test" }))
          }
          if (path === "/v1/speech/start") {
            return Promise.resolve(response({ capture_id: fake.captureId, state: "listening" }))
          }
          if (path === "/v1/speech/status") {
            fake.speechStatusCalls += 1
            const reportError = fake.speechError && fake.speechStatusCalls > 1
            return Promise.resolve(response({
              capture_id: fake.captureId,
              state: reportError ? "error" : "listening",
              transcript: reportError ? "" : fake.transcript,
              ...(reportError ? { error: fake.speechError } : {})
            }))
          }
          if (path === "/v1/speech/stop") {
            return Promise.resolve(response({ capture_id: fake.captureId, state: "stopped", transcript: fake.transcript }))
          }
          if (path === "/v1/analyze") {
            fake.analyzeCalls += 1
            return Promise.resolve(response({ analysis: {
              summary: "The answer has a clear decision boundary.",
              clarity: "State the invariant before the implementation detail.",
              fluency: "Use a short transition between claims.",
              pace: "Pause after the trade-off.",
              grammar: "The sentence structure is controlled.",
              relevance: "The response stays with the authored question.",
              pronunciation: "Transcript-aware only; this is not an acoustic score.",
              limitations: "No objective CEFR or guaranteed phonetic claim is made.",
              first_person_example: "I would verify the invariant before changing the implementation."
            } }))
          }
          if (path === "/v1/cleanup") {
            fake.cleanupCalls += 1
            return Promise.resolve(response({ ok: true }))
          }
          return Promise.resolve(response({ error: "not_found" }, 404))
        }
      })()
    JAVASCRIPT
  end

  def install_realtime_fake
    page.execute_script(<<~'JAVASCRIPT')
      (() => {
        const fake = window.__voiceRealtimeFake = {
          peers: [],
          channels: [],
          micDenied: false,
          captureDurationTimer: false,
          durationCallback: null,
          clock: 0
        }
        const nativeSetInterval = window.setInterval.bind(window)
        const nativeClearInterval = window.clearInterval.bind(window)
        window.setInterval = (callback, delay, ...args) => {
          if (fake.captureDurationTimer && delay === 1_000) {
            fake.captureDurationTimer = false
            fake.durationCallback = () => callback(...args)
            return "realtime-duration"
          }
          return nativeSetInterval(callback, delay, ...args)
        }
        window.clearInterval = (identifier) => {
          if (identifier === "realtime-duration") return
          nativeClearInterval(identifier)
        }

        class FakeChannel {
          constructor() {
            this.readyState = "open"
            this.sent = []
          }
          send(payload) { this.sent.push(payload) }
          emit(payload) { this.onmessage?.({ data: JSON.stringify(payload) }) }
          close() {
            this.readyState = "closed"
          }
        }
        class FakePeer {
          constructor() {
            this.connectionState = "new"
            this.iceConnectionState = "connected"
            this.iceGatheringState = "complete"
            this.closed = false
            this.senders = []
            fake.peers.push(this)
          }
          addTransceiver() {
            const sender = { replaceTrack: () => Promise.resolve() }
            this.senders.push(sender)
            return { sender }
          }
          createDataChannel() {
            this.dataChannel = new FakeChannel()
            fake.channels.push(this.dataChannel)
            return this.dataChannel
          }
          createOffer() { return Promise.resolve({ type: "offer", sdp: "v=0\\r\\nfake-offer\\r\\n" }) }
          setLocalDescription(description) { this.localDescription = description; return Promise.resolve() }
          setRemoteDescription() {
            this.connectionState = "connected"
            this.onconnectionstatechange?.()
            return Promise.resolve()
          }
          getSenders() { return this.senders }
          close() {
            this.closed = true
            this.connectionState = "closed"
          }
        }
        window.RTCPeerConnection = FakePeer
        Object.defineProperty(navigator, "mediaDevices", {
          configurable: true,
          value: {
            getUserMedia: () => fake.micDenied
              ? Promise.reject(new Error("permission denied"))
              : Promise.resolve({
                getAudioTracks: () => [ { enabled: true, stop() {} } ],
                getTracks() { return this.getAudioTracks() }
              })
          }
        })
        Object.defineProperty(window.performance, "now", { configurable: true, value: () => fake.clock })
      })()
    JAVASCRIPT
  end
end

require "application_system_test_case"

class EnglishArcadeVoiceTest < ApplicationSystemTestCase
  setup do
    ArcadeExerciseEvent.delete_all
    ArcadeLesson.delete_all
    ArcadeStageState.delete_all
    @learner_key = ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end

  test "Arena Speak shadows locally without pairing or Realtime" do
    lesson = visit_speak_lesson
    install_local_speech_fake

    assert_text(/Arena never enables OpenAI Realtime/i)
    assert_no_selector "[data-arena-realtime]"
    assert_no_selector "[data-english-arcade-voice-target]"
    assert find("button", text: "Start Apple Speech").disabled?

    click_button "Listen to model"
    assert_text(/Reading the model locally/i)
    assert_equal [ @speak_model_text ], page.evaluate_script("window.__arenaSpeakFake.spoken")
    assert_equal 0, page.evaluate_script("window.__arenaSpeakFake.loopbackCalls")

    select "3 · good", from: "Self-rate (1–4)"
    click_button "Save speaking pass"
    assert_selector ".arena-feedback:not([hidden])", wait: 5
    assert_text(/Held/i)
    assert_equal "active", lesson.reload.status
  end

  test "Arena Speak pairs a fake local companion, captures, and cleans up" do
    visit_speak_lesson
    install_companion_fake
    secret = "arena-system-test-secret"

    fill_in "Pairing secret (session only)", with: secret
    click_button "Pair companion"
    assert_text(/Apple Speech companion paired/i)
    refute find("button", text: "Start Apple Speech").disabled?
    assert_equal secret, page.evaluate_script("window.sessionStorage.getItem('english_arcade_voice_pairing')")
    assert_nil page.evaluate_script("window.localStorage.getItem('english_arcade_voice_pairing')")
    assert_browser_script "window.__arenaSpeakFake.requests.some((request) => request.path === '/v1/status')"
    assert_browser_script "window.__arenaSpeakFake.requests.every((request) => !request.url.includes('arena-system-test-secret') && !request.body.includes('arena-system-test-secret'))"

    click_button "Start Apple Speech"
    assert_button_enabled "Stop capture"
    click_button "Stop capture"
    assert_text(/Apple Speech stopped.*transcript is ready/i, wait: 5)
    assert_field "Optional transcript", with: /verify the invariant/i
    assert_browser_script "window.__arenaSpeakFake.requests.some((request) => request.path === '/v1/speech/start')"
    assert_browser_script "window.__arenaSpeakFake.requests.some((request) => request.path === '/v1/speech/stop')"

    page.execute_script(<<~JAVASCRIPT)
      (() => {
        const root = document.querySelector("section.arena-lesson")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "arcade-lesson")
        controller.disconnect()
      })()
    JAVASCRIPT
    assert_browser_script "window.__arenaSpeakFake.requests.some((request) => request.path === '/v1/cleanup')"
  end

  private

  def visit_speak_lesson
    visit "/arena"
    page.execute_script("window.localStorage.clear(); window.sessionStorage.clear()")

    content = ArcadeContent.new
    item = content.items_for("dsa").first
    exercise = content.build(item, stage: "speak", slot: 0)
    @speak_model_text = item.fetch(:best_answer)
    lesson = ArcadeLesson.create!(
      learner_key: @learner_key,
      target_mode: "single",
      target: item.fetch(:target),
      targets: [ item.fetch(:target) ],
      status: "active",
      seed: "system-speak",
      started_at: Time.current,
      exercises_total: 1,
      plan: [
        {
          "exercise_id" => exercise.fetch("exercise_id"),
          "factory_exercise_id" => exercise.fetch("exercise_id"),
          "card_key" => item.fetch(:key),
          "target" => item.fetch(:target),
          "stage" => "speak",
          "type" => "speak",
          "slot" => 0,
          "position" => 0,
          "reason" => "practice",
          "attempt_no" => 1,
          "boss" => false
        }
      ]
    )
    visit arcade_lesson_path(lesson)
    assert_selector ".arena-lesson[data-controller='arcade-lesson']"
    lesson
  end

  def assert_button_enabled(label)
    assert_selector "button", text: label, wait: 5
    refute find("button", text: label).disabled?, "#{label} should be enabled"
  end

  def assert_browser_script(script)
    assert page.evaluate_script(script), "Expected browser expression to be truthy: #{script}"
  end

  def install_local_speech_fake
    page.execute_script(<<~'JAVASCRIPT')
      (() => {
        const fake = window.__arenaSpeakFake = { spoken: [], cancelCalls: 0, loopbackCalls: 0 }
        const nativeFetch = window.fetch.bind(window)
        window.fetch = (input, init = {}) => {
          const url = typeof input === "string" ? input : input.url
          if (url.startsWith("http://127.0.0.1:43129")) {
            fake.loopbackCalls += 1
            return Promise.reject(new TypeError("unpaired Speak must not call the companion"))
          }
          return nativeFetch(input, init)
        }
        class FakeUtterance {
          constructor(text) { this.text = text; this.lang = ""; this.onend = null; this.onerror = null }
        }
        Object.defineProperty(window, "SpeechSynthesisUtterance", { configurable: true, writable: true, value: FakeUtterance })
        Object.defineProperty(window, "speechSynthesis", {
          configurable: true,
          value: {
            speak(utterance) { fake.spoken.push(utterance.text); utterance.onend?.() },
            cancel() { fake.cancelCalls += 1 }
          }
        })
      })()
    JAVASCRIPT
  end

  def install_companion_fake
    page.execute_script(<<~'JAVASCRIPT')
      (() => {
        const fake = window.__arenaSpeakFake = {
          requests: [],
          captureId: "arena-capture-1",
          transcript: "I would verify the invariant before changing the implementation."
        }
        const response = (body, status = 200) => Promise.resolve({
          ok: status >= 200 && status < 300,
          status,
          json: () => Promise.resolve(body)
        })
        window.fetch = (input, init = {}) => {
          const url = typeof input === "string" ? input : input.url
          if (!url.startsWith("http://127.0.0.1:43129")) return Promise.reject(new TypeError("unexpected non-companion request"))
          const rawHeaders = init.headers || {}
          const headers = typeof rawHeaders.get === "function" ? Object.fromEntries(rawHeaders.entries()) : { ...rawHeaders }
          const request = { url, path: new URL(url).pathname, method: init.method || "GET", headers, body: init.body || "" }
          fake.requests.push(request)
          switch (request.path) {
            case "/v1/status": return response({ companion: "ready", apple: { available: true, state: "idle" }, codex: { state: "signed_out" } })
            case "/v1/speech/start": return response({ capture_id: fake.captureId, state: "listening" })
            case "/v1/speech/status": return response({ capture_id: fake.captureId, state: "listening", transcript: fake.transcript })
            case "/v1/speech/stop": return response({ capture_id: fake.captureId, state: "stopped", transcript: fake.transcript })
            case "/v1/cleanup": return response({ ok: true })
            default: return response({ error: "not_found" }, 404)
          }
        }
      })()
    JAVASCRIPT
  end
end

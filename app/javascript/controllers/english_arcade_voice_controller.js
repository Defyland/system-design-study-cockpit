import { Controller } from "@hotwired/stimulus"

const PROVIDERS = Object.freeze([ "apple_codex", "openai_realtime" ])
const PROVIDER_STORAGE_KEY = "english_arcade_voice_provider"
const PAIRING_STORAGE_KEY = "english_arcade_voice_pairing"
const COMPANION_BASE_URL = "http://127.0.0.1:43129"
const COMPANION_PATHS = Object.freeze([
  "/v1/status",
  "/v1/login",
  "/v1/speech/start",
  "/v1/speech/status",
  "/v1/speech/stop",
  "/v1/analyze",
  "/v1/cleanup"
])
const REQUEST_TIMEOUT_MS = 10_000
const APPLE_MAX_DURATION_SECONDS = 10 * 60
const APPLE_POLL_INTERVAL_MS = 500
const APPLE_TRANSCRIPT_MAX_BYTES = 64 * 1024
const APPLE_CONTEXT_MAX_BYTES = 8 * 1024
const ANALYSIS_FIELDS = Object.freeze([
  [ "summary", "Summary" ],
  [ "clarity", "Clarity" ],
  [ "fluency", "Fluency" ],
  [ "pace", "Pace" ],
  [ "grammar", "Grammar" ],
  [ "relevance", "Relevance" ],
  [ "pronunciation", "Pronunciation" ],
  [ "limitations", "Limitations" ],
  [ "first_person_example", "Safe first-person example" ]
])

// The controller keeps the two billing/lifecycle boundaries explicit. Apple
// uses only local browser speech plus the loopback companion; Realtime keeps
// the existing Rails/WebRTC path and never becomes an implicit fallback.
export default class extends Controller {
  static targets = [
    "provider", "providerCopy", "appleControls", "realtimeControls", "realtimeUnavailable", "modelControls", "model",
    "pairingSecret", "pair", "refreshStatus", "login", "companionStatus", "enable",
    "listenQuestion", "listenAnswer", "stopSpeaking", "startMicrophone", "stopMicrophone", "analyze", "end", "clearTranscript",
    "status", "timer", "remoteAudio", "transcript", "feedback", "error"
  ]

  static values = {
    callUrl: String,
    sessionId: String,
    cardKey: String,
    question: String,
    answer: String,
    context: String,
    model: String,
    realtimeAvailable: Boolean,
    realtimeDefaultModel: String,
    realtimeQualityModel: String,
    companionBaseUrl: String,
    maxDurationSeconds: Number
  }

  connect() {
    this.peerConnection = null
    this.dataChannel = null
    this.microphoneStream = null
    this.microphoneSender = null
    this.microphoneTransceiver = null
    this.transcriptEntries = []
    this.transcriptSequence = 0
    this.appleTranscript = ""
    this.appleCaptureId = null
    this.applePollTimer = null
    this.applePollInFlight = false
    this.applePollDeadline = null
    this.appleCaptureStartedAt = null
    this.companionConnected = false
    this.appleAvailable = null
    this.codexState = "unavailable"
    this.localEnabled = false
    this.pairingBusy = false
    this.provider = this.readProvider()
    this.pairingSecret = this.readPairingSecret()
    this.connected = false
    this.startedAt = null
    this.elapsedSeconds = 0
    this.durationTimer = null
    this.tearingDown = false
    this.speaking = false
    this.speakingToken = 0
    this.setMaxDuration()
    this.handlePageHide = this.handlePageHide.bind(this)
    this.handleBeforeCache = this.handleBeforeCache.bind(this)
    this.handleProviderChange = this.handleProviderChange.bind(this)
    this.handlePairingSync = this.handlePairingSync.bind(this)
    window.addEventListener("pagehide", this.handlePageHide)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)
    window.addEventListener("english-arcade-voice:provider-change", this.handleProviderChange)
    window.addEventListener("english-arcade-voice:pairing-sync", this.handlePairingSync)
    if (this.hasPairingSecretTarget && this.pairingSecret) this.pairingSecretTarget.value = this.pairingSecret
    if (this.hasModelTarget) this.modelTarget.value = this.realtimeDefaultModelValue || this.modelValue
    this.setProviderUi()
    this.setStatus(this.provider === "apple_codex"
      ? "Apple Speech + Codex selected. Pair the local companion for speaking and analysis."
      : "OpenAI Realtime selected. It uses separate Platform billing.")
  }

  disconnect() {
    this.cleanup({ announce: false, clearTranscript: true, resetCompanion: true })
    window.removeEventListener("pagehide", this.handlePageHide)
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)
    window.removeEventListener("english-arcade-voice:provider-change", this.handleProviderChange)
    window.removeEventListener("english-arcade-voice:pairing-sync", this.handlePairingSync)
  }

  readProvider() {
    try {
      const value = window.localStorage.getItem(PROVIDER_STORAGE_KEY)
      return PROVIDERS.includes(value) ? value : "apple_codex"
    } catch (_error) {
      return "apple_codex"
    }
  }

  readPairingSecret() {
    try {
      return window.sessionStorage.getItem(PAIRING_STORAGE_KEY) || ""
    } catch (_error) {
      return ""
    }
  }

  persistProvider() {
    try { window.localStorage.setItem(PROVIDER_STORAGE_KEY, this.provider) } catch (_error) { /* browser storage may be unavailable */ }
  }

  setMaxDuration() {
    const configured = Number(this.maxDurationSecondsValue)
    this.maxDurationSeconds = Number.isFinite(configured) && configured > 0
      ? Math.min(configured, APPLE_MAX_DURATION_SECONDS)
      : APPLE_MAX_DURATION_SECONDS
  }

  chooseProvider(event) {
    const nextProvider = event.currentTarget.value
    if (!PROVIDERS.includes(nextProvider)) {
      event.currentTarget.value = this.provider
      return
    }
    if (nextProvider === this.provider) return

    this.cleanup({ announce: false, resetCompanion: true })
    this.provider = nextProvider
    this.persistProvider()
    this.broadcastProvider()
    this.clearError()
    this.setProviderUi()
    this.setStatus(nextProvider === "apple_codex"
      ? "Apple Speech + Codex selected. Pair the local companion when you need speaking or analysis."
      : "OpenAI Realtime selected. It is separately billed through the OpenAI Platform.")
  }

  handleProviderChange(event) {
    if (event.detail?.source === this) return
    const nextProvider = event.detail?.provider
    if (!PROVIDERS.includes(nextProvider) || nextProvider === this.provider) return

    this.cleanup({ announce: false, resetCompanion: true })
    this.provider = nextProvider
    this.persistProvider()
    this.clearError()
    this.setProviderUi()
  }

  broadcastProvider() {
    window.dispatchEvent(new CustomEvent("english-arcade-voice:provider-change", {
      detail: { provider: this.provider, source: this }
    }))
  }

  handlePairingSync(event) {
    if (event.detail?.source === this) return
    const secret = event.detail?.secret
    if (typeof secret !== "string") return

    this.pairingSecret = secret
    this.companionConnected = false
    this.appleAvailable = null
    this.codexState = "unavailable"
    if (this.hasPairingSecretTarget) this.pairingSecretTarget.value = secret
    this.setProviderUi()
  }

  broadcastPairing(secret) {
    window.dispatchEvent(new CustomEvent("english-arcade-voice:pairing-sync", {
      detail: { secret, source: this }
    }))
  }

  chooseModel(event) {
    if (this.provider !== "openai_realtime") {
      event.currentTarget.value = this.modelValue
      return
    }
    this.modelValue = event.currentTarget.value
  }

  async enableVoice() {
    this.clearError()
    if (this.provider === "apple_codex") {
      if (!this.canSpeakLocally()) {
        this.showError("Local browser speech synthesis is unavailable. The companion can still be paired for on-device capture.")
        return
      }
      this.localEnabled = true
      this.setStatus("Local Apple Speech reading is enabled. Pair the companion separately for on-device capture and Codex analysis.")
      this.setProviderUi()
      return
    }
    await this.enableRealtime()
  }

  async pairCompanion() {
    if (this.provider !== "apple_codex") return
    const value = this.hasPairingSecretTarget ? this.pairingSecretTarget.value.trim() : this.pairingSecret
    if (!value) {
      this.showError("Paste the one-time local companion pairing secret first. Guided reading remains available.")
      return
    }

    this.pairingSecret = value
    this.setStatus("Connecting to the local Apple Speech companion…")
    this.setPairingBusy(true)
    try {
      const status = await this.companionFetch("/v1/status")
      try { window.sessionStorage.setItem(PAIRING_STORAGE_KEY, value) } catch (_error) { /* session storage is best effort */ }
      this.broadcastPairing(value)
      this.applyCompanionStatus(status)
      this.setStatus("Apple companion connected. Local reading is ready; start the microphone when you consent.")
    } catch (error) {
      this.companionConnected = false
      this.setPairingBusy(false)
      this.showError(this.companionErrorMessage(error, "The local companion could not be reached. Guided reading remains available."))
    }
  }

  async refreshCompanionStatus() {
    if (!this.pairingSecret) {
      this.showError("Pair the local companion before refreshing status.")
      return
    }
    this.setStatus("Refreshing local companion status…")
    try {
      const status = await this.companionFetch("/v1/status")
      this.applyCompanionStatus(status)
      this.setStatus("Companion status refreshed. No account identity is shown here.")
    } catch (error) {
      this.companionConnected = false
      this.setPairingBusy(false)
      this.showError(this.companionErrorMessage(error, "The local companion status request failed."))
    }
  }

  applyCompanionStatus(payload) {
    this.companionConnected = true
    this.appleAvailable = payload?.apple?.available === true
    const state = payload?.codex?.state?.toString()
    this.codexState = [ "signed_out", "login_pending", "signed_in", "unavailable" ].includes(state) ? state : "unavailable"
    const appleState = payload?.apple?.state?.toString() || "unavailable"
    const appleText = this.appleAvailable ? `Apple Speech companion: ${appleState}.` : "On-device Apple Speech is unavailable; there is no cloud fallback."
    const codexText = {
      signed_out: " Codex: signed out; sign in with the managed ChatGPT flow for analysis.",
      login_pending: " Codex: login pending; finish the browser sign-in, then refresh status.",
      signed_in: " Codex: signed in with the managed ChatGPT account.",
      unavailable: " Codex: unavailable; transcript capture can continue locally."
    }[this.codexState]
    if (this.hasCompanionStatusTarget) this.companionStatusTarget.textContent = appleText + codexText
    this.setPairingBusy(false)
    this.setProviderUi()
  }

  async startManagedLogin() {
    if (this.provider !== "apple_codex" || !this.companionConnected) {
      this.showError("Pair the local companion before starting managed ChatGPT login.")
      return
    }

    // Open synchronously from the click handler, then navigate only after the
    // companion returns an HTTPS managed-login URL. No credentials are read.
    let popup = null
    try { popup = window.open("about:blank", "_blank") } catch (_error) { popup = null }
    if (popup) {
      try { popup.opener = null } catch (_error) { /* browser may expose a read-only opener */ }
    }
    this.setStatus("Starting the managed ChatGPT/Codex login…")
    try {
      const result = await this.companionFetch("/v1/login", { method: "POST", body: {} })
      const authUrl = typeof result?.authUrl === "string" ? result.authUrl : ""
      let parsedUrl
      try { parsedUrl = new URL(authUrl) } catch (_error) { parsedUrl = null }
      if (!parsedUrl || parsedUrl.protocol !== "https:") {
        try { popup?.close?.() } catch (_error) { /* popup cleanup is best effort */ }
        throw this.errorWithCode("invalid_login_url")
      }
      if (!popup || popup.closed) throw this.errorWithCode("popup_blocked")
      popup.location.href = parsedUrl.href
      this.codexState = result?.state === "login_pending" ? "login_pending" : this.codexState
      this.setProviderUi()
      this.setStatus("Managed login opened. Finish it in the browser, then refresh companion status.")
    } catch (error) {
      try { popup?.close?.() } catch (_closeError) { /* popup cleanup is best effort */ }
      this.showError(error.code === "invalid_login_url"
        ? "The companion returned an invalid login link; no page was opened."
        : error.code === "popup_blocked"
          ? "The login popup was blocked. Allow popups for this page and try again; no provider fallback was made."
        : this.companionErrorMessage(error, "Managed ChatGPT login could not be started."))
    }
  }

  companionFetch(path, { method = "GET", body = undefined, query = "", keepalive = false } = {}) {
    if (!COMPANION_PATHS.includes(path)) return Promise.reject(this.errorWithCode("invalid_companion_path"))
    if (!this.pairingSecret) return Promise.reject(this.errorWithCode("pairing_required"))

    const controller = new AbortController()
    const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS)
    const headers = { Accept: "application/json", "X-English-Arcade-Pairing": this.pairingSecret }
    if (body !== undefined) headers["Content-Type"] = "application/json"
    const request = {
      method,
      headers,
      credentials: "omit",
      signal: controller.signal,
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      ...(keepalive ? { keepalive: true } : {})
    }
    return window.fetch(`${COMPANION_BASE_URL}${path}${query}`, request).then(async (response) => {
      let payload = null
      try { payload = await response.json() } catch (_error) { /* generic error below */ }
      if (!response.ok) throw this.errorWithCode(payload?.error || (response.status === 401 ? "pairing_required" : "companion_unavailable"))
      if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw this.errorWithCode("companion_unavailable")
      return payload
    }).catch((error) => {
      if (error?.code) throw error
      throw this.errorWithCode(error?.name === "AbortError" ? "timeout" : "network_error")
    }).finally(() => window.clearTimeout(timeout))
  }

  errorWithCode(code) {
    const error = new Error("voice companion request failed")
    error.code = code
    return error
  }

  companionErrorMessage(error, fallback) {
    return {
      pairing_required: "The pairing secret was rejected. Check the local terminal value; no provider fallback was made.",
      origin_not_allowed: "This page origin is not allowlisted by the companion.",
      timeout: "The local companion request timed out. Guided reading remains available.",
      network_error: "The local companion could not be reached. Guided reading remains available.",
      companion_unavailable: "The local companion is unavailable. Guided reading remains available.",
      speech_permission_denied: "Speech recognition permission was denied. Local reading remains available.",
      microphone_permission_denied: "Microphone permission was denied. Local reading remains available.",
      on_device_recognition_unavailable: "On-device Apple Speech is unavailable on this Mac; there is no cloud fallback.",
      microphone_unavailable: "The local microphone is unavailable. Local reading remains available.",
      speech_capture_failed: "Apple Speech capture failed. The temporary transcript, if any, remains on this page.",
      capture_timeout: "Apple Speech reached its ten-minute limit and was stopped.",
      invalid_login_url: "The companion returned an invalid login link; no page was opened."
    }[error?.code] || fallback
  }

  setPairingBusy(busy) {
    this.pairingBusy = Boolean(busy)
    if (this.hasPairTarget) this.pairTarget.disabled = this.pairingBusy
    if (this.hasRefreshStatusTarget) this.refreshStatusTarget.disabled = this.pairingBusy || !this.pairingSecret
    if (this.hasLoginTarget) this.loginTarget.disabled = this.pairingBusy || !this.companionConnected
  }

  canSpeakLocally() {
    return typeof window.speechSynthesis !== "undefined" && typeof window.SpeechSynthesisUtterance !== "undefined"
  }

  listenQuestion() {
    if (this.provider === "apple_codex") {
      if (!this.localEnabled) {
        this.setStatus("Enable local Apple Speech reading before listening to the exact question.")
        return
      }
      this.speakLocally(this.questionValue, "question")
      return
    }
    this.requestRealtimeSpeech("Read the exact authored question from the authoritative card once, without adding content.")
  }

  listenAnswer() {
    if (this.provider === "apple_codex") {
      if (!this.localEnabled) {
        this.setStatus("Enable local Apple Speech reading before listening to the exact answer.")
        return
      }
      this.speakLocally(this.answerValue, "answer")
      return
    }
    this.requestRealtimeSpeech("Read the exact authored best answer from the authoritative card once, preserving its caveats.")
  }

  speakLocally(text, label) {
    if (!this.canSpeakLocally()) {
      this.showError("Local browser speech synthesis is unavailable. Guided reading remains available.")
      return
    }
    const value = text.toString()
    if (!value.trim()) {
      this.showError(`The authored ${label} is empty; Guided reading remains available.`)
      return
    }
    this.cancelLocalSpeech({ announce: false })
    const token = ++this.speakingToken
    const utterance = new window.SpeechSynthesisUtterance(value)
    utterance.lang = "en-US"
    utterance.onstart = () => {
      if (token !== this.speakingToken) return
      this.speaking = true
      this.setProviderUi()
      this.setStatus(`Reading the exact authored ${label} locally…`)
    }
    utterance.onend = () => {
      if (token !== this.speakingToken) return
      this.speaking = false
      this.setProviderUi()
      this.setStatus("Local reading finished. Repeat it or start the microphone when ready.")
    }
    utterance.onerror = () => {
      if (token !== this.speakingToken) return
      this.speaking = false
      this.setProviderUi()
      this.showError("Local speech playback failed. Guided reading remains available.")
    }
    this.currentUtterance = utterance
    this.speaking = true
    window.speechSynthesis.speak(utterance)
    this.setProviderUi()
  }

  stopSpeaking() {
    this.cancelLocalSpeech({ announce: true })
  }

  cancelLocalSpeech({ announce = false } = {}) {
    this.speakingToken += 1
    try { window.speechSynthesis?.cancel?.() } catch (_error) { /* browser speech cleanup is best effort */ }
    this.speaking = false
    this.currentUtterance = null
    this.setProviderUi()
    if (announce) this.setStatus("Local speech stopped.")
  }

  async startMicrophone() {
    if (this.provider === "apple_codex") {
      await this.startAppleCapture()
      return
    }
    await this.startRealtimeMicrophone()
  }

  async startAppleCapture() {
    if (!this.companionConnected) {
      this.setStatus("Pair the local companion before starting Apple Speech capture.")
      return
    }
    if (this.appleAvailable !== true) {
      this.showError("On-device Apple Speech is unavailable or not yet paired; there is no cloud fallback.")
      return
    }
    if (this.appleCaptureId) return

    this.clearError()
    this.elapsedSeconds = 0
    this.renderTimer()
    this.setStatus("Requesting on-device Apple Speech microphone access…")
    try {
      const result = await this.companionFetch("/v1/speech/start", { method: "POST", body: { language: "en-US" } })
      if (typeof result?.capture_id !== "string" || result.capture_id.length === 0) throw this.errorWithCode("companion_unavailable")
      this.appleCaptureId = result.capture_id
      this.appleCaptureStartedAt = performance.now()
      this.applePollDeadline = this.appleCaptureStartedAt + APPLE_MAX_DURATION_SECONDS * 1000
      this.startDurationTimer()
      this.startApplePolling()
      this.setProviderUi()
      if (result.state === "error") this.setStatus("Apple Speech reported an error; checking its bounded status.")
      else this.setStatus("Apple Speech listening on this Mac. Speak when ready; no browser audio upload is used.")
    } catch (error) {
      this.showError(this.companionErrorMessage(error, "Apple Speech could not start. Guided reading remains available."))
    }
  }

  startApplePolling() {
    this.clearApplePolling()
    const poll = async () => {
      if (!this.appleCaptureId || this.applePollInFlight) return
      if (this.applePollDeadline && performance.now() >= this.applePollDeadline) {
        await this.stopAppleCapture({ announce: false, reason: "Apple Speech reached its ten-minute limit and was stopped." })
        return
      }
      this.applePollInFlight = true
      const captureId = this.appleCaptureId
      try {
        const result = await this.companionFetch("/v1/speech/status", {
          query: `?capture_id=${encodeURIComponent(captureId)}`
        })
        if (captureId !== this.appleCaptureId) return
        if (typeof result?.transcript === "string") {
          this.appleTranscript = this.boundText(result.transcript, APPLE_TRANSCRIPT_MAX_BYTES)
          this.renderAppleTranscript()
        }
        if (result?.error) {
          const message = this.companionErrorMessage({ code: result.error }, "Apple Speech capture failed.")
          this.finishAppleCapture()
          this.showError(message)
          return
        }
        if (result?.state === "stopped") {
          this.finishAppleCapture()
          this.setStatus("Apple Speech stopped. Review the temporary transcript, then analyze it if Codex is signed in.")
          return
        }
      } catch (error) {
        if (captureId === this.appleCaptureId) {
          this.finishAppleCapture()
          this.showError(this.companionErrorMessage(error, "Apple Speech status polling failed."))
        }
        return
      } finally {
        this.applePollInFlight = false
      }
      if (captureId === this.appleCaptureId) this.applePollTimer = window.setTimeout(poll, APPLE_POLL_INTERVAL_MS)
    }
    poll()
  }

  async stopMicrophone(options = {}) {
    const announce = options?.announce !== false
    if (this.provider === "apple_codex") {
      await this.stopAppleCapture({ announce })
      return
    }
    this.stopRealtimeMicrophone({ announce })
  }

  async stopAppleCapture({ announce = true, reason = null } = {}) {
    const captureId = this.appleCaptureId
    if (!captureId) return
    this.clearApplePolling()
    this.clearDurationTimer()
    this.appleCaptureId = null
    this.applePollDeadline = null
    this.appleCaptureStartedAt = null
    let shouldAnalyze = false
    try {
      const result = await this.companionFetch("/v1/speech/stop", { method: "POST", body: { capture_id: captureId } })
      if (typeof result?.transcript === "string") {
        this.appleTranscript = this.boundText(result.transcript, APPLE_TRANSCRIPT_MAX_BYTES)
        this.renderAppleTranscript()
      }
      if (result?.error) {
        this.showError(this.companionErrorMessage({ code: result.error }, "Apple Speech capture failed."))
      } else if (reason) {
        this.setStatus(reason)
      } else if (announce) {
        this.setStatus("Microphone off. The temporary transcript remains on this page.")
      }
      shouldAnalyze = !result?.error && Boolean(this.appleTranscript.trim()) && this.codexState === "signed_in"
    } catch (error) {
      this.showError(this.companionErrorMessage(error, "Apple Speech could not be stopped cleanly."))
    } finally {
      this.setProviderUi()
    }
    if (shouldAnalyze) await this.analyzeTranscript()
  }

  finishAppleCapture() {
    this.clearApplePolling()
    this.clearDurationTimer()
    this.appleCaptureId = null
    this.applePollDeadline = null
    this.appleCaptureStartedAt = null
    this.setProviderUi()
  }

  clearApplePolling() {
    window.clearTimeout(this.applePollTimer)
    this.applePollTimer = null
  }

  async analyzeTranscript() {
    if (this.provider !== "apple_codex") {
      this.setStatus("OpenAI Realtime feedback appears in its temporary transcript; no provider switch was made.")
      return
    }
    if (!this.appleTranscript.trim()) {
      this.setStatus("Capture a transcript before requesting Codex feedback.")
      return
    }
    if (this.codexState !== "signed_in") {
      this.setStatus("Transcript kept on this page. Sign in with managed ChatGPT/Codex, refresh status, then analyze; no fallback was made.")
      return
    }

    this.clearError()
    this.setStatus("Sending the temporary transcript to the local companion for Codex analysis…")
    try {
      const result = await this.companionFetch("/v1/analyze", {
        method: "POST",
        body: {
          question: this.boundText(this.questionValue, 8 * 1024),
          answer: this.boundText(this.answerValue, 8 * 1024),
          context: this.boundText(this.contextValue, APPLE_CONTEXT_MAX_BYTES),
          transcript: this.boundText(this.appleTranscript, APPLE_TRANSCRIPT_MAX_BYTES)
        }
      })
      this.renderFeedback(result?.analysis)
      this.setStatus("Codex feedback received. Pronunciation notes are transcript-aware, not an acoustic score.")
    } catch (error) {
      this.showError(this.companionErrorMessage(error, "Codex analysis failed; the temporary transcript remains on this page."))
    }
  }

  renderAppleTranscript() {
    this.transcriptEntries = this.appleTranscript
      ? [ { id: "apple-transcript", kind: "input", speaker: "You", text: this.appleTranscript, finalized: true } ]
      : []
    this.renderTranscript()
    this.setProviderUi()
  }

  renderFeedback(analysis) {
    if (!this.hasFeedbackTarget) return
    const heading = document.createElement("p")
    heading.textContent = "Codex feedback · rehearsal only; pronunciation is transcript-aware, not an acoustic score."
    const definitionList = document.createElement("dl")
    ANALYSIS_FIELDS.forEach(([ key, label ]) => {
      const term = document.createElement("dt")
      term.textContent = label
      const detail = document.createElement("dd")
      detail.textContent = typeof analysis?.[key] === "string" ? analysis[key] : "Not provided by the companion."
      definitionList.append(term, detail)
    })
    this.feedbackTarget.replaceChildren(heading, definitionList)
    this.feedbackTarget.hidden = false
  }

  clearTranscript() {
    this.transcriptEntries = []
    this.appleTranscript = ""
    if (this.hasTranscriptTarget) this.transcriptTarget.replaceChildren()
    if (this.hasFeedbackTarget) {
      this.feedbackTarget.replaceChildren()
      this.feedbackTarget.hidden = true
    }
    this.clearError()
    this.setProviderUi()
    this.setStatus(this.connected || this.appleCaptureId ? "Transcript cleared. The current session is still active." : "Transcript cleared.")
  }

  endVoice() {
    this.cleanup({
      announce: false,
      resetCompanion: true,
      status: "Voice ended and cleaned up. Guided reading remains available."
    })
  }

  async enableRealtime() {
    if (!this.realtimeAvailableValue) {
      this.showError("OpenAI Realtime is unavailable without its server-side flag and Platform key. Apple Speech remains a separate provider.")
      return
    }
    if (this.connected) return
    if (!window.RTCPeerConnection) {
      this.showError("This browser cannot establish the OpenAI Realtime connection.")
      return
    }

    this.setStatus("Preparing the explicitly selected OpenAI Realtime connection…")
    try {
      this.peerConnection = new RTCPeerConnection()
      this.microphoneTransceiver = this.peerConnection.addTransceiver("audio", { direction: "sendrecv" })
      this.peerConnection.ontrack = (event) => this.attachRemoteTrack(event)
      this.peerConnection.onconnectionstatechange = () => this.handleConnectionState()
      this.peerConnection.oniceconnectionstatechange = () => this.handleIceState()
      this.dataChannel = this.peerConnection.createDataChannel("oai-events")
      this.dataChannel.onopen = () => this.setStatus("OpenAI Realtime connected. Platform billing applies; microphone use is optional.")
      this.dataChannel.onmessage = (event) => this.handleRealtimeEvent(event)
      this.dataChannel.onerror = () => this.handleTransportFailure("The OpenAI Realtime data channel ended. No provider fallback was made.")
      this.dataChannel.onclose = () => this.handleTransportFailure("The OpenAI Realtime data channel closed. No provider fallback was made.")

      const offer = await this.peerConnection.createOffer()
      await this.peerConnection.setLocalDescription(offer)
      await this.waitForIceGathering()
      const answer = await this.createServerCall(this.peerConnection.localDescription?.sdp)
      await this.peerConnection.setRemoteDescription({ type: "answer", sdp: answer })
      this.connected = true
      this.startedAt = performance.now()
      this.elapsedSeconds = 0
      this.startDurationTimer()
      this.setConnectedUi(true)
      this.setStatus("OpenAI Realtime connected. Choose a listening action or start the microphone when ready.")
    } catch (error) {
      this.cleanup({ announce: false })
      this.showError(error.message || "OpenAI Realtime setup failed. No provider fallback was made.")
    }
  }

  requestRealtimeSpeech(instruction) {
    if (this.provider !== "openai_realtime" || !this.connected || !this.dataChannel || this.dataChannel.readyState !== "open") {
      this.setStatus("Connect OpenAI Realtime before requesting its temporary audio.")
      return
    }
    try {
      this.dataChannel.send(JSON.stringify({
        type: "response.create",
        response: { output_modalities: [ "audio" ], instructions: instruction }
      }))
      this.setStatus("Requesting temporary OpenAI Realtime audio…")
    } catch (_error) {
      this.handleTransportFailure("The OpenAI Realtime data channel ended. No provider fallback was made.")
    }
  }

  async createServerCall(sdp) {
    if (!sdp || sdp.trim().length === 0) throw new Error("The browser did not produce a valid SDP offer.")

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const abortController = new AbortController()
    const timeout = window.setTimeout(() => abortController.abort(), REQUEST_TIMEOUT_MS)
    let response
    try {
      response = await fetch(this.callUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/sdp, application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({
          sdp,
          session_id: this.sessionIdValue,
          card_key: this.cardKeyValue,
          model: this.modelValue
        }),
        signal: abortController.signal
      })
    } catch (error) {
      if (error.name === "AbortError") throw new Error("OpenAI Realtime setup timed out. No provider fallback was made.")
      throw new Error("The OpenAI Realtime network request failed. No provider fallback was made.")
    } finally {
      window.clearTimeout(timeout)
    }
    if (response.ok) return response.text()

    let payload = null
    try { payload = await response.json() } catch (_error) { /* safe generic mapping below */ }
    const messages = {
      voice_unavailable: "OpenAI Realtime is unavailable right now.",
      invalid_sdp: "The browser produced an invalid OpenAI Realtime offer.",
      invalid_model: "That OpenAI Realtime model is not available.",
      session_not_found: "This study session is no longer available.",
      guided_session_required: "Voice rehearsal is available only in guided study.",
      session_inactive: "This guided session is no longer active.",
      card_not_found: "That authored card is no longer available.",
      budget_exhausted: "The daily OpenAI Realtime rehearsal allowance has been reached.",
      upstream_unavailable: "OpenAI Realtime is unavailable; no provider fallback was made."
    }
    throw new Error(messages[payload?.error] || "OpenAI Realtime setup failed. No provider fallback was made.")
  }

  async startRealtimeMicrophone() {
    if (this.provider !== "openai_realtime" || !this.connected || !navigator.mediaDevices?.getUserMedia) {
      this.setStatus("Connect OpenAI Realtime before starting its microphone.")
      return
    }
    if (this.microphoneStream) return

    this.clearError()
    try {
      this.microphoneStream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const track = this.microphoneStream.getAudioTracks()[0]
      if (!track) throw new Error("No microphone track was granted.")
      this.microphoneSender = this.microphoneTransceiver?.sender
      if (!this.microphoneSender) throw new Error("The OpenAI Realtime connection has no audio sender.")
      await this.microphoneSender.replaceTrack(track)
      this.setConnectedUi(true)
      this.setStatus("OpenAI Realtime microphone on. Speak naturally; temporary audio/transcript uses Platform billing.")
    } catch (_error) {
      this.stopRealtimeMicrophone({ announce: false })
      this.showError("Microphone access was denied or unavailable. OpenAI Realtime listening remains available.")
    }
  }

  stopRealtimeMicrophone({ announce = true } = {}) {
    const stream = this.microphoneStream
    const sender = this.microphoneSender
    this.microphoneStream = null
    this.microphoneSender = null
    try {
      stream?.getTracks().forEach((track) => {
        track.enabled = false
        track.stop()
      })
    } catch (_error) { /* track cleanup is best effort */ }
    try {
      const replacement = sender?.replaceTrack?.(null)
      replacement?.catch?.(() => {})
    } catch (_error) { /* sender cleanup is best effort */ }
    if (announce && this.connected) this.setStatus("Microphone off. OpenAI Realtime listening remains available.")
    this.setConnectedUi(this.connected)
  }

  attachRemoteTrack(event) {
    const stream = event.streams?.[0]
    if (!stream || !this.hasRemoteAudioTarget) return
    this.remoteAudioTarget.srcObject = stream
    this.remoteAudioTarget.hidden = false
    const playback = this.remoteAudioTarget.play?.()
    playback?.catch?.(() => {})
  }

  handleRealtimeEvent(event) {
    let payload
    try { payload = JSON.parse(event.data) } catch (_error) { return }
    const type = payload?.type?.toString() || ""
    if (type.includes("error")) {
      this.handleTransportFailure("OpenAI Realtime reported a session error. No provider fallback was made.")
      return
    }

    const inputTranscript = type.includes("input_audio_transcription") || type.includes("conversation.item.input_audio")
    const speaker = inputTranscript ? "You" : "Coach"
    const final = type.endsWith(".done") || type.endsWith(".completed") || type.includes("transcription.completed")
    const completedText = [ payload.transcript, payload.text ].find((value) => typeof value === "string")
    const text = final && completedText !== undefined
      ? completedText
      : [ payload.delta, completedText ].find((value) => typeof value === "string") || ""
    if (text.length === 0) return
    const identities = this.transcriptIdentities(payload, speaker)
    this.upsertTranscript({ speaker, text, identities, final, replaceOnFinal: final && completedText !== undefined })
    if (speaker === "Coach" && final) this.setFeedbackMessage("OpenAI Realtime transcript feedback received; pronunciation is not an acoustic score here.")
  }

  transcriptIdentities(payload, speaker) {
    const rawIds = [ payload?.item_id, payload?.item?.id, payload?.response_id, payload?.response?.id ]
    return [ ...new Set(rawIds.filter((value) => value).map((value) => `${speaker.toLowerCase()}:${value}`)) ]
  }

  upsertTranscript({ speaker, text, identities, final, replaceOnFinal }) {
    const kind = speaker === "You" ? "input" : "coach"
    let entry = this.transcriptEntries.find((candidate) => identities.some((identity) => candidate.id === identity || candidate.aliases?.includes(identity)))
    if (!entry && identities.length === 0) {
      entry = [ ...this.transcriptEntries ].reverse().find((candidate) => candidate.kind === kind && !candidate.finalized)
    }
    if (entry?.finalized && final) {
      if (replaceOnFinal || text.length >= entry.text.length) entry.text = text
      this.renderTranscript()
      return
    }
    if (!entry || entry.finalized) {
      entry = {
        id: identities[0] || `${kind}:${++this.transcriptSequence}`,
        aliases: identities,
        kind,
        speaker,
        text: "",
        finalized: false
      }
      this.transcriptEntries.push(entry)
    }

    if (final) {
      if (replaceOnFinal) entry.text = text
      else if (!entry.text.endsWith(text)) entry.text += text
      entry.finalized = true
    } else {
      entry.text += text
    }
    this.renderTranscript()
  }

  renderTranscript() {
    if (!this.hasTranscriptTarget) return
    this.transcriptTarget.replaceChildren(...this.transcriptEntries.map((entry) => {
      const line = document.createElement("p")
      line.textContent = `${entry.speaker}: ${entry.text}`
      return line
    }))
    this.transcriptTarget.lastElementChild?.scrollIntoView?.({ block: "nearest" })
  }

  setFeedbackMessage(message) {
    if (!this.hasFeedbackTarget) return
    const paragraph = document.createElement("p")
    paragraph.textContent = message
    this.feedbackTarget.replaceChildren(paragraph)
    this.feedbackTarget.hidden = false
  }

  handleConnectionState() {
    const state = this.peerConnection?.connectionState
    if ([ "failed", "disconnected", "closed" ].includes(state)) {
      this.handleTransportFailure("The OpenAI Realtime network connection ended. No provider fallback was made.")
    }
  }

  handleIceState() {
    if ([ "failed", "disconnected" ].includes(this.peerConnection?.iceConnectionState)) {
      this.handleTransportFailure("The OpenAI Realtime ICE connection failed. No provider fallback was made.")
    }
  }

  handleTransportFailure(message) {
    if (this.tearingDown) return
    if (!this.peerConnection && !this.dataChannel && !this.connected) return
    this.cleanup({ announce: false })
    this.showError(message)
  }

  async waitForIceGathering() {
    if (!this.peerConnection || this.peerConnection.iceGatheringState === "complete") return
    await new Promise((resolve) => {
      let timeoutId
      const finish = () => {
        if (this.peerConnection?.iceGatheringState !== "complete") return
        window.clearTimeout(timeoutId)
        this.peerConnection.removeEventListener("icegatheringstatechange", finish)
        resolve()
      }
      const expire = () => {
        this.peerConnection?.removeEventListener("icegatheringstatechange", finish)
        resolve()
      }
      timeoutId = window.setTimeout(expire, 3_000)
      this.peerConnection.addEventListener("icegatheringstatechange", finish)
      finish()
    })
  }

  startDurationTimer() {
    this.clearDurationTimer()
    this.durationTimer = window.setInterval(() => {
      const startedAt = this.startedAt || this.appleCaptureStartedAt
      if (!startedAt) return
      this.elapsedSeconds = Math.floor((performance.now() - startedAt) / 1_000)
      this.renderTimer()
      if (this.elapsedSeconds >= Math.min(this.maxDurationSeconds, APPLE_MAX_DURATION_SECONDS)) {
        if (this.provider === "apple_codex" && this.appleCaptureId) {
          this.stopAppleCapture({ announce: false, reason: "Apple Speech reached its ten-minute limit and was stopped." })
        } else if (this.connected) {
          this.cleanup({ status: "The ten-minute OpenAI Realtime duration was reached; the connection was cleaned up." })
        }
      }
    }, 1_000)
    this.renderTimer()
  }

  clearDurationTimer() {
    window.clearInterval(this.durationTimer)
    this.durationTimer = null
  }

  renderTimer() {
    if (!this.hasTimerTarget) return
    const minutes = Math.floor(this.elapsedSeconds / 60).toString().padStart(2, "0")
    const seconds = (this.elapsedSeconds % 60).toString().padStart(2, "0")
    this.timerTarget.textContent = `${minutes}:${seconds}`
  }

  cleanup({ announce = false, clearTranscript = false, status = null, resetCompanion = false } = {}) {
    if (this.tearingDown) return
    this.tearingDown = true
    const terminalStatus = status || (announce ? "Voice ended and cleaned up. Guided reading remains available." : null)
    const cleanupCompanion = this.provider === "apple_codex" && this.companionConnected && Boolean(this.pairingSecret)
    this.clearApplePolling()
    this.clearDurationTimer()
    this.cancelLocalSpeech({ announce: false })
    this.stopRealtimeMicrophone({ announce: false })

    if (cleanupCompanion) {
      this.companionFetch("/v1/cleanup", { method: "POST", body: {}, keepalive: true }).catch(() => {})
    }
    this.appleCaptureId = null
    this.applePollDeadline = null
    this.appleCaptureStartedAt = null
    this.localEnabled = false
    if (resetCompanion) {
      this.companionConnected = false
      this.appleAvailable = null
      this.codexState = "unavailable"
    }

    const channel = this.dataChannel
    this.dataChannel = null
    if (channel) {
      channel.onopen = null
      channel.onmessage = null
      channel.onerror = null
      channel.onclose = null
      try { channel.close() } catch (_error) { /* channel may already be closed */ }
    }

    const peer = this.peerConnection
    this.peerConnection = null
    if (peer) {
      peer.ontrack = null
      peer.onconnectionstatechange = null
      peer.oniceconnectionstatechange = null
      try {
        peer.getSenders?.().forEach((sender) => {
          const replacement = sender.replaceTrack?.(null)
          replacement?.catch?.(() => {})
        })
      } catch (_error) { /* sender cleanup is best effort */ }
      try { peer.close() } catch (_error) { /* peer may already be closed */ }
    }

    this.microphoneTransceiver = null
    this.connected = false
    this.startedAt = null
    this.elapsedSeconds = 0
    if (this.hasRemoteAudioTarget) {
      try { this.remoteAudioTarget.pause() } catch (_error) { /* media may already be paused */ }
      this.remoteAudioTarget.srcObject = null
      this.remoteAudioTarget.hidden = true
    }
    if (clearTranscript) {
      this.transcriptEntries = []
      this.appleTranscript = ""
      if (this.hasTranscriptTarget) this.transcriptTarget.replaceChildren()
      if (this.hasFeedbackTarget) {
        this.feedbackTarget.replaceChildren()
        this.feedbackTarget.hidden = true
      }
    }
    this.setConnectedUi(false)
    if (terminalStatus) this.setStatus(terminalStatus)
    this.tearingDown = false
  }

  setAvailabilityUi() {
    this.setProviderUi()
  }

  setProviderUi() {
    const apple = this.provider === "apple_codex"
    if (this.hasProviderTarget) this.providerTarget.value = this.provider
    if (this.hasAppleControlsTarget) this.appleControlsTarget.hidden = !apple
    if (this.hasRealtimeControlsTarget) this.realtimeControlsTarget.hidden = apple
    if (this.hasRealtimeUnavailableTarget) this.realtimeUnavailableTarget.hidden = apple || this.realtimeAvailableValue
    if (this.hasProviderCopyTarget) {
      this.providerCopyTarget.textContent = apple
        ? "Apple Speech + Codex is the recommended local provider: browser TTS and macOS on-device listening stay local; managed Codex feedback uses your ChatGPT/Codex plan."
        : "OpenAI Realtime API is an explicit Platform-billed provider; it is not included in a ChatGPT subscription and never becomes a fallback."
    }
    if (this.hasModelTarget) {
      this.modelTarget.disabled = apple || this.connected || !this.realtimeAvailableValue
      if (!apple && !this.modelTarget.value) this.modelTarget.value = this.realtimeDefaultModelValue || this.modelValue
    }
    if (this.hasEnableTarget) {
      this.enableTarget.disabled = !apple && (!this.realtimeAvailableValue || this.connected)
      this.enableTarget.textContent = apple ? "Enable local Apple Speech + Codex" : "Enable OpenAI Realtime API"
    }
    if (this.hasPairTarget) this.pairTarget.disabled = !apple || this.pairingBusy
    if (this.hasRefreshStatusTarget) this.refreshStatusTarget.disabled = !apple || this.pairingBusy || !this.companionConnected
    if (this.hasLoginTarget) this.loginTarget.disabled = !apple || this.pairingBusy || !this.companionConnected
    if (this.hasListenQuestionTarget) this.listenQuestionTarget.disabled = apple ? !this.localEnabled || !this.canSpeakLocally() : !this.connected
    if (this.hasListenAnswerTarget) this.listenAnswerTarget.disabled = apple ? !this.localEnabled || !this.canSpeakLocally() : !this.connected
    if (this.hasStopSpeakingTarget) this.stopSpeakingTarget.disabled = !this.speaking
    if (this.hasStartMicrophoneTarget) this.startMicrophoneTarget.disabled = apple
      ? !this.companionConnected || this.appleAvailable !== true || Boolean(this.appleCaptureId)
      : !this.connected || Boolean(this.microphoneStream)
    if (this.hasStopMicrophoneTarget) this.stopMicrophoneTarget.disabled = apple ? !this.appleCaptureId : !this.microphoneStream
    if (this.hasAnalyzeTarget) this.analyzeTarget.disabled = apple ? !this.appleTranscript.trim() || this.codexState !== "signed_in" : true
    if (this.hasEndTarget) this.endTarget.disabled = apple
      ? !(this.localEnabled || this.companionConnected || this.appleCaptureId || this.speaking)
      : !this.connected
    if (this.hasRemoteAudioTarget) this.remoteAudioTarget.hidden = apple || !this.connected
  }

  setConnectedUi(connected) {
    this.connected = connected
    this.setProviderUi()
  }

  boundText(value, maxBytes) {
    const text = value?.toString?.() || ""
    if (typeof TextEncoder === "undefined") return text.slice(0, maxBytes)
    const encoder = new TextEncoder()
    if (encoder.encode(text).length <= maxBytes) return text
    let result = ""
    for (const character of text) {
      const next = result + character
      if (encoder.encode(next).length > maxBytes) break
      result = next
    }
    return result
  }

  showError(message) {
    if (this.hasErrorTarget) this.errorTarget.textContent = message
    this.setStatus("Voice needs attention; no provider fallback was made.")
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.textContent = ""
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  handlePageHide() {
    this.cleanup({ announce: false, clearTranscript: true, resetCompanion: true })
  }

  handleBeforeCache() {
    this.cleanup({ announce: false, clearTranscript: true, resetCompanion: true })
  }
}

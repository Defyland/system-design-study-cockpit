import { escape, addSubmit } from "arcade/exercise_helpers"

const DEFAULT_BASE_URL = "http://127.0.0.1:43129"
const PAIRING_KEY = "english_arcade_voice_pairing"
const PATHS = new Set(["/v1/status", "/v1/speech/start", "/v1/speech/status", "/v1/speech/stop", "/v1/analyze", "/v1/cleanup"])
const TIMEOUT_MS = 10_000

// The Arena deliberately has no Realtime path. It can use the existing local
// companion only after explicit session-only pairing; otherwise it remains a
// complete browser-shadowing/self-rating exercise.
export function render(root, exercise, ctx) {
  const model = exercise.payload?.model_text || ""
  const baseUrl = loopbackBaseUrl(ctx.companionBaseUrl)
  const state = { pairing: readPairing(), paired: false, apple: false, codex: false, captureId: null, poll: null, disposed: false }
  root.innerHTML = `<p class="arena-eyebrow">Speak · shadow or transcribe</p><h2>${escape(exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><p class="arena-instruction">Shadow the exact model and save a self-rating. Browser reading always works. The optional local Apple Speech + Codex companion captures only when you pair it; Arena never enables OpenAI Realtime.</p><div class="arena-exercise-actions"><button type="button" class="arena-button arena-button-secondary" data-arena-speak-listen>Listen to model</button><button type="button" class="arena-button arena-button-quiet" data-arena-speak-stop disabled>Stop reading</button></div><section class="arena-speak-companion" aria-label="Optional local Apple Speech companion"><p><strong>Optional local companion</strong> · Pairing stays in this browser session and is sent only as a loopback request header, never to Rails.</p><label for="arena-pairing">Pairing secret (session only)</label><div class="arena-exercise-actions"><input id="arena-pairing" class="arena-input" type="password" autocomplete="off" spellcheck="false" placeholder="Paste local companion secret"><button type="button" class="arena-button arena-button-quiet" data-arena-speak-pair>Pair companion</button></div><p class="arena-muted" data-arena-speak-status role="status" aria-live="polite">Shadowing is ready locally. Pairing is optional.</p><div class="arena-exercise-actions"><button type="button" class="arena-button arena-button-secondary" data-arena-speak-capture disabled>Start Apple Speech</button><button type="button" class="arena-button arena-button-quiet" data-arena-speak-stop-capture disabled>Stop capture</button></div><p class="arena-muted" data-arena-speak-analysis hidden></p></section><label for="arena-response">Optional transcript</label><textarea id="arena-response" class="arena-input" rows="5" autocomplete="off" placeholder="Leave blank to self-rate shadowing"></textarea><label for="arena-self-rating">Self-rate (1–4)</label><select id="arena-self-rating" class="arena-input"><option value="">Choose</option><option value="1">1 · again</option><option value="2">2 · hard</option><option value="3">3 · good</option><option value="4">4 · easy</option></select>`
  const $ = (selector) => root.querySelector(selector)
  const listen = $("[data-arena-speak-listen]")
  const stopReading = $("[data-arena-speak-stop]")
  const secret = $("#arena-pairing")
  const pair = $("[data-arena-speak-pair]")
  const capture = $("[data-arena-speak-capture]")
  const stopCapture = $("[data-arena-speak-stop-capture]")
  const status = $("[data-arena-speak-status]")
  const analysis = $("[data-arena-speak-analysis]")
  const transcript = $("#arena-response")
  secret.value = state.pairing
  const say = (message) => { status.textContent = message }
  const syncCapture = () => { capture.disabled = !state.paired || !state.apple || Boolean(state.captureId); stopCapture.disabled = !state.captureId }
  const stopLocalReading = () => { try { window.speechSynthesis?.cancel?.() } catch (_error) { /* best effort */ }; stopReading.disabled = true }
  const renderAnalysis = (value) => { analysis.textContent = value; analysis.hidden = false }
  const analyze = async () => {
    if (!state.codex || !transcript.value.trim()) return
    say("Sending the temporary transcript to the local companion for Codex coaching…")
    try {
      const result = await companionFetch(baseUrl, state.pairing, "/v1/analyze", { method: "POST", body: { question: exercise.prompt || "", answer: model, context: exercise.context || "", transcript: boundText(transcript.value) } })
      const notes = [result.analysis?.summary, result.analysis?.clarity, result.analysis?.limitations].filter((value) => typeof value === "string" && value.trim())
      renderAnalysis(notes.join(" ") || "Codex returned no additional coaching.")
      say("Local companion coaching is ready. It is not an objective pronunciation score.")
    } catch (_error) { say("Transcript retained locally; Codex coaching was unavailable. No provider fallback was used.") }
  }
  const stopCaptureRequest = async ({ cleanup = false } = {}) => {
    const id = state.captureId
    if (!id) return
    state.captureId = null
    window.clearTimeout(state.poll)
    syncCapture()
    try {
      const result = await companionFetch(baseUrl, state.pairing, "/v1/speech/stop", { method: "POST", body: { capture_id: id } })
      if (typeof result.transcript === "string") transcript.value = boundText(result.transcript)
      if (!cleanup) {
        if (state.codex) await analyze()
        else say("Apple Speech stopped. Your temporary transcript is ready to review.")
      }
    } catch (_error) { if (!cleanup) say("Apple Speech stopped, but no transcript was returned. Shadowing remains available.") }
  }
  const poll = async () => {
    if (!state.captureId || state.disposed) return
    const id = state.captureId
    try {
      const result = await companionFetch(baseUrl, state.pairing, "/v1/speech/status", { query: `?capture_id=${encodeURIComponent(id)}` })
      if (id !== state.captureId) return
      if (typeof result.transcript === "string") transcript.value = boundText(result.transcript)
      if (result.error || result.state === "stopped") return stopCaptureRequest()
      state.poll = window.setTimeout(poll, 600)
    } catch (_error) { state.captureId = null; syncCapture(); say("Apple Speech status is unavailable. Shadowing remains available; no cloud fallback was used.") }
  }
  listen.addEventListener("click", () => {
    if (!model || !window.speechSynthesis) return say("Browser speech synthesis is unavailable. You can still shadow by reading the model after feedback.")
    stopLocalReading()
    const utterance = new SpeechSynthesisUtterance(model)
    utterance.lang = "en-US"
    utterance.onend = utterance.onerror = () => { stopReading.disabled = true }
    window.speechSynthesis.speak(utterance)
    stopReading.disabled = false
    ctx.audio?.play("listen")
    say("Reading the model locally. Repeat aloud, then self-rate when ready.")
  })
  stopReading.addEventListener("click", () => { stopLocalReading(); say("Local reading stopped.") })
  pair.addEventListener("click", async () => {
    const value = secret.value.trim()
    if (!value) return say("Paste the one-time local companion pairing secret, or continue shadowing without it.")
    state.pairing = value
    say("Checking the local Apple Speech companion…")
    try {
      const result = await companionFetch(baseUrl, value, "/v1/status")
      state.paired = true
      state.apple = result.apple?.available === true
      state.codex = result.codex?.state === "signed_in"
      try { window.sessionStorage.setItem(PAIRING_KEY, value) } catch (_error) { /* session-only storage is best effort */ }
      syncCapture()
      say(state.apple ? "Apple Speech companion paired. Start capture only when you consent." : "Companion paired, but Apple Speech is unavailable on this Mac. Shadowing remains available.")
    } catch (_error) {
      state.paired = false
      state.apple = false
      state.codex = false
      syncCapture()
      say("The local companion could not be paired. Shadowing remains available; no cloud fallback was used.")
    }
  })
  capture.addEventListener("click", async () => {
    try {
      const result = await companionFetch(baseUrl, state.pairing, "/v1/speech/start", { method: "POST", body: { language: "en-US" } })
      if (typeof result.capture_id !== "string" || !result.capture_id) throw new Error("capture unavailable")
      state.captureId = result.capture_id
      syncCapture()
      ctx.audio?.play("start")
      say("Apple Speech is listening on this Mac. Browser audio is not uploaded.")
      poll()
    } catch (_error) { say("Apple Speech could not start. Shadowing remains available; no cloud fallback was used.") }
  })
  stopCapture.addEventListener("click", async () => { ctx.audio?.play("stop"); await stopCaptureRequest() })
  addSubmit(root, ctx, "Save speaking pass")
  ctx.cleanup.push(() => {
    state.disposed = true
    stopLocalReading()
    if (state.captureId) stopCaptureRequest({ cleanup: true })
    else if (state.paired) companionFetch(baseUrl, state.pairing, "/v1/cleanup", { method: "POST", body: {}, keepalive: true }).catch(() => {})
  })
}

export function collect(root) { return { response_text: root.querySelector("#arena-response")?.value || "", self_rating: root.querySelector("#arena-self-rating")?.value || "" } }

function readPairing() { try { return window.sessionStorage.getItem(PAIRING_KEY) || "" } catch (_error) { return "" } }
function boundText(value) { return String(value || "").slice(0, 16_000) }

function loopbackBaseUrl(value) {
  try {
    const url = new URL(value || DEFAULT_BASE_URL)
    if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" || url.username || url.password || url.pathname !== "/" || url.search || url.hash) return DEFAULT_BASE_URL
    return url.origin
  } catch (_error) { return DEFAULT_BASE_URL }
}

async function companionFetch(baseUrl, secret, path, { method = "GET", body, query = "", keepalive = false } = {}) {
  if (!PATHS.has(path) || !secret) throw new Error("companion unavailable")
  const controller = new AbortController()
  const timeout = window.setTimeout(() => controller.abort(), TIMEOUT_MS)
  try {
    const headers = { Accept: "application/json", "X-English-Arcade-Pairing": secret }
    if (body !== undefined) headers["Content-Type"] = "application/json"
    const response = await window.fetch(`${baseUrl}${path}${query}`, { method, headers, credentials: "omit", signal: controller.signal, ...(body === undefined ? {} : { body: JSON.stringify(body) }), ...(keepalive ? { keepalive: true } : {}) })
    const payload = await response.json().catch(() => null)
    if (!response.ok || !payload || typeof payload !== "object" || Array.isArray(payload)) throw new Error("companion unavailable")
    return payload
  } finally { window.clearTimeout(timeout) }
}

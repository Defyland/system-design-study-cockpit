import { Controller } from "@hotwired/stimulus"
import { LessonMachine } from "arcade/lesson_machine"
import * as meet from "arcade/exercises/meet"
import * as chooseBest from "arcade/exercises/choose_best"
import * as trapAxis from "arcade/exercises/trap_axis"
import * as cloze from "arcade/exercises/cloze"
import * as rebuild from "arcade/exercises/rebuild"
import * as produce from "arcade/exercises/produce"
import * as speak from "arcade/exercises/speak"
import * as transfer from "arcade/exercises/transfer"
import * as compress from "arcade/exercises/compress"
import * as feynman from "arcade/exercises/feynman"
import * as rain from "arcade/exercises/rain"
import { escape } from "arcade/exercise_helpers"

const RENDERERS = Object.freeze({ meet, choose_best: chooseBest, trap_axis: trapAxis, cloze, rebuild, produce, speak, transfer, compress, feynman, rain })

export default class extends Controller {
  static values = { id: Number, resultUrl: String, finishUrl: String }
  static targets = ["exercise", "feedback", "results", "progress", "position", "stage", "target", "combo", "exitDialog", "dossierDialog", "dossierCopy", "helpDialog"]

  connect() {
    this.destroyed = false
    this.busy = false
    this.paused = false
    this.combo = 0
    this.lessonStartedAt = performance.now()
    this.startedAt = this.lessonStartedAt
    this.lastFocus = null
    this.keyboardHandler = null
    this.lessonData = this.readData()
    this.exercises = this.lessonData.exercises || []
    this.machine = new LessonMachine(this.exercises.length)
    this.machine.start(this.lessonData.resume_position || 0)
    this.renderCurrent()
    this.boundKeydown = (event) => this.handleKeydown(event)
    document.addEventListener("keydown", this.boundKeydown)
    ;[this.exitDialogTarget, this.dossierDialogTarget, this.helpDialogTarget].forEach((dialog) => dialog?.addEventListener("cancel", (event) => event.preventDefault()))
  }

  disconnect() {
    this.destroyed = true
    document.removeEventListener("keydown", this.boundKeydown)
    this.cleanupExercise?.()
  }

  readData() {
    try { return JSON.parse(this.element.querySelector("#arcade-lesson-data")?.textContent || "{}") } catch (_error) { return {} }
  }

  get current() { return this.exercises[this.machine.position] }

  renderCurrent() {
    if (this.destroyed || this.machine.state === "results") return this.finishLesson()
    const exercise = this.current
    if (!exercise) return this.finishLesson()
    const renderer = RENDERERS[exercise.type] || chooseBest
    this.cleanupExercise?.()
    this.keyboardHandler = null
    this.exerciseTarget.innerHTML = ""
    const context = { submit: () => this.submit(), keyboard: null, cleanup: [] }
    renderer.render(this.exerciseTarget, exercise, context)
    this.cleanupExercise = () => context.cleanup.forEach((callback) => callback())
    this.keyboardHandler = context.keyboard
    this.updateHud(exercise)
    this.focusFirstControl()
  }

  updateHud(exercise) {
    const total = Math.max(this.exercises.length, 1)
    this.positionTarget.textContent = String(this.machine.position + 1)
    this.progressTarget.style.width = `${Math.round((this.machine.position / total) * 100)}%`
    this.stageTarget.textContent = String(exercise.stage || exercise.type || "Exercise").replaceAll("_", " ")
    this.targetTarget.textContent = String(exercise.target || "mixed").replaceAll("_", " ")
    this.comboTarget.textContent = `Combo ${this.combo}`
  }

  focusFirstControl() {
    window.requestAnimationFrame(() => {
      const first = this.exerciseTarget.querySelector("button, textarea, select, input")
      first?.focus()
    })
  }

  handleKeydown(event) {
    const tag = event.target?.tagName?.toLowerCase()
    const editing = tag === "textarea" || tag === "input" || tag === "select"
    const interactive = event.target?.closest?.("button, [role='button'], [data-arena-chunk]")
    if (event.key === "Escape") {
      if (this.dossierDialogTarget?.open) return this.closeDossier()
      if (this.helpDialogTarget?.open) return this.closeHelp()
      if (!this.exitDialogTarget?.open) this.openExit()
      return
    }
    if (event.key === " " && !editing) {
      if (interactive && this.exerciseTarget.contains(interactive)) { event.preventDefault(); return interactive.click() }
      if (interactive) return

      event.preventDefault(); return this.pause()
    }
    if (event.key.toLowerCase() === "d" && !editing) { event.preventDefault(); return this.openDossier() }
    if (event.key === "?" && !editing) { event.preventDefault(); return this.openHelp() }
    if (editing) return
    if (/^[1-6]$/.test(event.key) && this.keyboardHandler) { event.preventDefault(); this.keyboardHandler(event.key); return }
    if (event.key === "Enter") {
      if (interactive) {
        if (this.exerciseTarget.contains(interactive) && interactive.matches("[data-arena-chunk]")) { event.preventDefault(); interactive.click() }
        return
      }

      event.preventDefault(); return this.feedbackTarget.hidden ? this.submit() : this.next()
    }
  }

  pause() {
    this.paused = !this.paused
    this.exerciseTarget.toggleAttribute("inert", this.paused)
    this.exerciseTarget.classList.toggle("is-paused", this.paused)
    if (this.paused) {
      const notice = document.createElement("p"); notice.className = "arena-instruction"; notice.dataset.arenaPauseNotice = "true"; notice.textContent = "Paused · press Space to resume"; this.exerciseTarget.prepend(notice)
    } else this.exerciseTarget.querySelector("[data-arena-pause-notice]")?.remove()
  }

  async submit() {
    if (this.busy || this.paused || !this.current) return
    const exercise = this.current
    const renderer = RENDERERS[exercise.type] || chooseBest
    const collected = renderer.collect(this.exerciseTarget) || {}
    this.busy = true
    this.machine.beginGrade()
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const body = { result: { exercise_id: exercise.exercise_id, response: collected.response, response_text: collected.response_text, response_ms: Math.max(0, Math.round(performance.now() - this.startedAt)), self_rating: collected.self_rating } }
    try {
      const response = await fetch(this.resultUrlValue, { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf || "" }, body: JSON.stringify(body) })
      const result = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(result.error || "Could not record this exercise")
      this.lastResult = result
      this.combo = result.correct ? this.combo + 1 : 0
      this.machine.showFeedback()
      this.renderFeedback(result)
    } catch (error) {
      this.machine.state = "exercise"
      this.showError(error.message)
    } finally { this.busy = false }
  }

  renderFeedback(result) {
    const reveal = result.reveal || {}
    const feedback = reveal.feedback || {}
    const wrong = !result.correct
    this.feedbackTarget.hidden = false
    this.feedbackTarget.classList.toggle("is-wrong", wrong)
    const feedbackLines = Object.entries(feedback).filter(([key, value]) => value && !["answer", "selected", "sources", "provenance"].includes(key)).slice(0, 6).map(([key, value]) => `<p><strong>${escape(key.replaceAll("_", " "))}:</strong> ${escape(value)}</p>`).join("")
    const why = reveal.why_wrong ? `<p><strong>Why this was weaker:</strong> ${escape(reveal.why_wrong)}</p>` : ""
    const axis = reveal.trap_axis || result.trap_axis
    const axisLine = axis ? `<span class="arena-axis">Trap axis · ${escape(axis)}</span>` : ""
    this.feedbackTarget.innerHTML = `<h2>${wrong ? "Not this time" : "Held"}</h2>${axisLine}<div class="arena-feedback-grid"><p class="arena-answer-reveal"><strong>Model answer:</strong> ${escape(reveal.best_answer || "Recorded. Keep the distinction explicit.")}</p>${why}${reveal.pt_help ? `<p><strong>Portuguese cue:</strong> ${escape(reveal.pt_help)}</p>` : ""}${feedbackLines}</div><div class="arena-exercise-actions"><button type="button" class="arena-button" data-arena-continue="true">${result.requeue ? "Try it again later" : "Continue"} <kbd>Enter</kbd></button></div>`
    this.feedbackTarget.querySelector("[data-arena-continue]")?.addEventListener("click", () => this.next())
    this.comboTarget.textContent = `Combo ${this.combo}`
    if (reveal.best_answer) {
      const feedback = reveal.feedback || {}
      const lines = Object.entries(feedback).filter(([key, value]) => value && !["sources", "provenance"].includes(key)).map(([key, value]) => `<p><strong>${escape(key.replaceAll("_", " "))}:</strong> ${escape(value)}</p>`).join("")
      this.dossierCopyTarget.innerHTML = `<p><strong>Model answer:</strong> ${escape(reveal.best_answer)}</p>${reveal.why_wrong ? `<p><strong>Trap:</strong> ${escape(reveal.why_wrong)}</p>` : ""}${lines}`
    } else this.dossierCopyTarget.innerHTML = "<p>Answer the exercise first to open its reference note. The Arena does not preload answer keys.</p>"
    if (reveal.best_answer && this.current?.type === "speak") {
      const listen = document.createElement("button"); listen.type = "button"; listen.className = "arena-button arena-button-secondary"; listen.textContent = "Listen to model answer"; listen.addEventListener("click", () => { if (window.speechSynthesis) window.speechSynthesis.speak(new SpeechSynthesisUtterance(reveal.best_answer)) }); this.feedbackTarget.querySelector(".arena-exercise-actions")?.prepend(listen)
    }
    this.feedbackTarget.querySelector("[data-arena-continue]")?.focus()
  }

  async next() {
    if (this.busy || !this.lastResult) return
    this.feedbackTarget.hidden = true
    this.feedbackTarget.innerHTML = ""
    const refreshed = await this.refreshLesson()
    if (!refreshed) return this.showError("The next exercise could not be loaded. Your result is saved; retry when connected.")
    this.lastResult = null
    if (this.machine.state === "results" || this.machine.position >= this.exercises.length) return this.finishLesson()
    this.renderCurrent()
  }

  async refreshLesson() {
    try {
      const response = await fetch(`${window.location.pathname}.json`, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) return false
      const payload = await response.json()
      const lesson = payload.lesson || payload
      this.exercises = lesson.exercises || this.exercises
      this.lessonData.resume_position = Number(lesson.resume_position || 0)
      this.machine.total = this.exercises.length
      this.machine.start(this.lessonData.resume_position)
      return true
    } catch (_error) { return false }
  }

  async finishLesson() {
    if (this.finished || this.finishing) return
    this.finishing = true
    try {
      const csrf = document.querySelector("meta[name='csrf-token']")?.content
      const response = await fetch(this.finishUrlValue, { method: "POST", credentials: "same-origin", headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf || "" }, body: JSON.stringify({ duration_ms: Math.round(performance.now() - this.lessonStartedAt) }) })
      const result = await response.json().catch(() => ({}))
      if (!response.ok && response.status !== 409) throw new Error(result.error || "Could not finish lesson")
      this.finished = true
      this.machine.results()
      this.renderResults(result)
    } catch (error) { this.showError(error.message) } finally { this.finishing = false }
  }

  renderResults(result) {
    this.exerciseTarget.hidden = true
    this.feedbackTarget.hidden = true
    this.resultsTarget.hidden = false
    const accuracy = Number(result.accuracy || 0)
    const cards = result.cards || result.summary?.cards || []
    const cardLines = cards.slice(0, 6).map((card) => `<li><strong>${escape(card.card_key)}</strong> · ${(Number(card.mastery?.score || 0) * 100).toFixed(0)}% mastery</li>`).join("")
    this.resultsTarget.innerHTML = `<p class="arena-eyebrow">Lesson complete</p><h2>${result.perfect ? "Perfect lesson." : "The next pass is clear."}</h2><div class="arena-results-grid"><div class="arena-result-stat"><strong>${Math.round(accuracy * 100)}%</strong><span>accuracy</span></div><div class="arena-result-stat"><strong>${result.max_combo || 0}</strong><span>max combo</span></div><div class="arena-result-stat"><strong>${Object.values(result.misses_by_axis || {}).reduce((sum, value) => sum + Number(value || 0), 0)}</strong><span>misses</span></div></div><h3>Cards that moved</h3><ul>${cardLines || "<li>Keep the first stage moving.</li>"}</ul><div class="arena-exercise-actions"><a class="arena-button" href="/arena">Return to hub</a><a class="arena-button arena-button-quiet" href="/arena">Again</a></div>`
    this.resultsTarget.focus()
  }

  showError(message) {
    this.feedbackTarget.hidden = false
    this.feedbackTarget.classList.add("is-wrong")
    this.feedbackTarget.innerHTML = `<h2>Connection paused</h2><p>${escape(message)}</p><button type="button" class="arena-button" data-arena-retry="true">Retry</button>`
    this.feedbackTarget.querySelector("[data-arena-retry]")?.addEventListener("click", () => { this.feedbackTarget.hidden = true; this.feedbackTarget.classList.remove("is-wrong"); if (this.lastResult) this.next() })
  }

  openDialog(dialog) { this.lastFocus = document.activeElement; dialog?.showModal(); dialog?.querySelector("button")?.focus() }
  restoreFocus(dialog) { dialog?.close(); if (this.lastFocus?.focus) this.lastFocus.focus(); this.lastFocus = null }
  openExit() { this.openDialog(this.exitDialogTarget) }
  closeDialog() { this.restoreFocus(this.exitDialogTarget) }
  openDossier() { this.openDialog(this.dossierDialogTarget) }
  closeDossier() { this.restoreFocus(this.dossierDialogTarget) }
  openHelp() { this.openDialog(this.helpDialogTarget) }
  closeHelp() { this.restoreFocus(this.helpDialogTarget) }
}

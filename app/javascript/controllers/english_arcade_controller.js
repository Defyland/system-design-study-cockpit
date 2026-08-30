import { Controller } from "@hotwired/stimulus"

// Guided rounds are deliberately deterministic. A completed round advances the
// level, while a miss only resets the streak; the authored card and its answer
// remain the source of truth for every option.
const GUIDED_GAME_INITIAL_FALL_MS = 9000
const GUIDED_GAME_MIN_FALL_MS = 4500
const GUIDED_GAME_FALL_STEP_MS = 750
const GUIDED_GAME_INITIAL_STAGGER_MS = 1400
const GUIDED_GAME_MIN_STAGGER_MS = 800
const GUIDED_GAME_STAGGER_STEP_MS = 100
const GUIDED_GAME_DEADLINE_BUFFER_MS = 350
const GUIDED_GAME_MIN_DEADLINE_MS = GUIDED_GAME_MIN_FALL_MS + (3 * GUIDED_GAME_MIN_STAGGER_MS) + GUIDED_GAME_DEADLINE_BUFFER_MS
const GUIDED_GAME_MAX_LEVEL = 8
const GUIDED_GAME_CLOCK_INTERVAL_MS = 100

// The controller owns interaction only. Assessment grading, answer keys,
// feedback, and Leitner transitions stay on the server; a refresh cannot turn
// the closed-book path into a client-side answer key. Guided study is a
// separate, non-assessing card reader: its only persisted client state is the
// learner's local self-rating and current position.
export default class extends Controller {
  static targets = [
    "choice", "form", "submit", "responseMs", "typed", "countdown", "feedback",
    "guidedBoard", "guidedCard", "guidedChoice", "guidedProgress", "guidedStatus",
    "guidedRatingStatus", "guidedPause", "guidedPrevious", "guidedNext"
  ]

  static values = {
    durationSeconds: Number,
    remainingSeconds: Number,
    active: Boolean,
    finishUrl: String,
    guided: Boolean,
    sessionKey: String
  }

  connect() {
    this.startedAt = performance.now()
    this.guidedIndex = 0
    this.guidedRatings = {}
    this.guidedUserPaused = false
    this.guidedReadingPaused = false
    this.guidedGameMode = "best_answer"
    this.guidedGameScore = 0
    this.guidedGameStreak = 0
    this.guidedGameLevel = 1
    this.guidedGameCorrect = 0
    this.guidedGameRounds = 0
    this.guidedGameTimeout = null
    this.guidedGameClock = null
    this.guidedGameRemainingMs = null
    this.guidedGameEndsAt = null
    this.expired = Boolean(this.guidedValue && this.sessionKeyValue !== "landing" && !this.activeValue)
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
    if (this.guidedValue) this.connectGuided()
    this.startCountdown()
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    if (this.timer) window.clearInterval(this.timer)
    this.clearGuidedGameClock()
  }

  handleKeydown(event) {
    if (this.guidedValue) {
      this.handleGuidedKeydown(event)
      return
    }
    if (!this.hasFormTarget || !this.activeValue) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (/^[1-4]$/.test(event.key)) {
      const target = this.choiceTargets[Number(event.key) - 1]
      if (target) {
        const input = target.querySelector("input")
        if (input) {
          input.checked = true
          input.dispatchEvent(new Event("change", { bubbles: true }))
          target.focus()
          event.preventDefault()
        }
      }
    } else if ((event.key === "Enter" || event.key === "Return") && document.activeElement?.tagName !== "TEXTAREA") {
      if (this.formTarget.querySelector("input[name*='answer_choice']:checked")) {
        event.preventDefault()
        if (this.hasResponseMsTarget) {
          this.responseMsTarget.value = Math.max(1, Math.round(performance.now() - this.startedAt))
        }
        // WebDriver and a few embedded browsers do not consistently dispatch
        // requestSubmit() from a label's synthetic Enter key. Calling the
        // native form submit keeps keyboard completion equivalent to clicking
        // the visible button and still sends only the checked choice.
        HTMLFormElement.prototype.submit.call(this.formTarget)
      }
    } else if (event.key === "Escape") {
      const first = this.formTarget.querySelector("input[name*='answer_choice']")
      first?.focus()
      event.preventDefault()
    }
  }

  connectGuided() {
    if (!this.hasGuidedCardTarget) return

    const progress = this.readGuidedProgress()
    this.guidedRatings = progress.ratings
    this.guidedIndex = Math.min(Math.max(progress.currentIndex, 0), this.guidedCardTargets.length - 1)
    this.renderGuidedCard({ focus: false, persist: false })
    this.resetGuidedGame({ announce: false })
    this.announceGuided(this.expired ? "Study time is complete. Gameplay is locked; the dossier remains available." : "Choose a game mode and start the round.")
  }

  handleGuidedKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (!this.hasGuidedCardTarget) return
    if (this.element.querySelector("[data-guided-learning-dialog][open]")) return

    const activeTag = document.activeElement?.tagName
    if (["INPUT", "TEXTAREA", "SELECT"].includes(activeTag)) return

    if (/^[1-4]$/.test(event.key)) {
      const gameOption = this.runningGuidedGameOptions()[Number(event.key) - 1]
      if (gameOption) {
        this.finishGuidedGameChoice(gameOption)
      } else {
        this.chooseGuidedOption(Number(event.key) - 1)
      }
      event.preventDefault()
    } else if (event.key === "ArrowRight" || event.key === "PageDown") {
      this.nextGuidedCard()
      event.preventDefault()
    } else if (event.key === "ArrowLeft" || event.key === "PageUp") {
      this.previousGuidedCard()
      event.preventDefault()
    } else if (event.key === " " || event.key.toLowerCase() === "p") {
      this.toggleGuidedPause()
      event.preventDefault()
    } else if (event.key === "Escape") {
      this.guidedBoardTarget.focus()
      event.preventDefault()
    }
  }

  selectGuidedChoice(event) {
    this.setGuidedChoice(event.currentTarget)
  }

  openCurrentGuidedLearningDialog() {
    this.openGuidedLearningDialog(this.currentGuidedCard())
  }

  openGuidedLearningDialog(container) {
    const dialog = container?.querySelector("[data-guided-learning-dialog]")
    if (!dialog || dialog.open) return

    if (this.currentGuidedGameStage()?.dataset.gameState === "running") {
      this.toggleGuidedGameClock(true)
      this.guidedReadingPaused = true
      this.setGuidedPauseUi(true)
    }
    if (typeof dialog.showModal === "function") dialog.showModal()
    else dialog.setAttribute("open", "")
    dialog.querySelector("[data-action*='closeGuidedLearningDialog']")?.focus()
  }

  closeGuidedLearningDialog(event) {
    const dialog = event.currentTarget.closest("dialog")
    if (!dialog) return

    if (typeof dialog.close === "function") dialog.close()
    else dialog.removeAttribute("open")
  }

  closeGuidedLearningDialogs() {
    this.element.querySelectorAll("[data-guided-learning-dialog][open]").forEach((dialog) => {
      if (typeof dialog.close === "function") dialog.close()
      else dialog.removeAttribute("open")
    })
  }

  async fillBestAnswer(event) {
    event.preventDefault()
    const form = event.currentTarget.closest("form")
    if (!form) return

    const button = event.currentTarget
    const status = form.querySelector("[data-best-answer-fill-status]")
    button.disabled = true
    if (status) status.textContent = "Loading the authored best answer…"

    let values
    try {
      const response = await fetch(form.dataset.bestAnswerFillUrl, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({
          session_id: this.sessionKeyValue,
          card_key: form.querySelector("input[name='english_arcade_attempt[card_key]']")?.value
        })
      })
      if (!response.ok) throw new Error(`Best answer request failed with ${response.status}`)
      values = await response.json()
    } catch (_error) {
      if (status) status.textContent = "The best answer could not be loaded. Your current work was not changed."
      return
    } finally {
      button.disabled = false
    }

    Array.from(form.elements).forEach((control) => {
      if (!control.name) return

      const match = control.name.match(/^english_arcade_attempt\[([^\]]+)\]$/)
      if (!match || !(match[1] in values)) return

      const value = String(values[match[1]])
      if (control.type === "radio" || control.type === "checkbox") {
        control.checked = control.value === value
      } else {
        control.value = value
      }
      control.closest("details")?.setAttribute("open", "")
      control.dispatchEvent(new Event("input", { bubbles: true }))
      control.dispatchEvent(new Event("change", { bubbles: true }))
    })

    if (status) status.textContent = "Best authored answer and all authored fields filled. Add your confidence and optional self-ratings before committing."
    form.querySelector("[data-english-arcade-target='typed']")?.focus()
  }

  chooseGuidedOption(index) {
    const card = this.guidedCardTargets[this.guidedIndex]
    const choice = card?.querySelector(`[data-guided-choice-index='${index}']`)
    if (choice) this.setGuidedChoice(choice)
  }

  setGuidedChoice(choice) {
    const card = choice.closest("[data-guided-card-index]")
    if (!card) return

    const index = Number(card.dataset.guidedCardIndex)
    if (Number.isInteger(index) && index !== this.guidedIndex) {
      this.guidedIndex = Math.min(Math.max(index, 0), this.guidedCardTargets.length - 1)
      this.renderGuidedCard({ focus: false, persist: false })
    }

    card.querySelectorAll("[data-guided-choice-index]").forEach((candidate) => {
      const selected = candidate === choice
      candidate.classList.toggle("is-selected", selected)
      candidate.setAttribute("aria-pressed", selected ? "true" : "false")
    })
    if (this.currentGuidedGameStage()?.dataset.gameState === "running") this.toggleGuidedGameClock(true)
    this.guidedReadingPaused = true
    this.setGuidedPauseUi(true)
    const number = Number(choice.dataset.guidedChoiceIndex) + 1
    const best = choice.classList.contains("is-best")
    this.announceGuided(`${best ? "Best authored option" : "Authored alternative"} ${number} selected. Paused for reading.`)
  }

  previousGuidedCard() {
    this.setGuidedIndex(this.guidedIndex - 1)
  }

  nextGuidedCard() {
    this.setGuidedIndex(this.guidedIndex + 1)
  }

  setGuidedIndex(index, { focus = true } = {}) {
    if (!this.hasGuidedCardTarget) return

    this.closeGuidedLearningDialogs()

    const nextIndex = Math.min(Math.max(index, 0), this.guidedCardTargets.length - 1)
    const interruptedRound = this.currentGuidedGameStage()?.dataset.gameState === "running"
    if (nextIndex === this.guidedIndex && this.guidedCardTargets[this.guidedIndex] && this.guidedCardTargets[this.guidedIndex].hidden === false) {
      if (interruptedRound) {
        this.resetGuidedGame({ announce: false })
        this.announceGuided("The current round was canceled at the edge of the deck. Start it again when ready.")
      }
      return
    }
    if (interruptedRound) this.resetGuidedGame({ announce: false })

    this.guidedIndex = nextIndex
    this.renderGuidedCard({ focus, persist: true })
    this.guidedReadingPaused = false
    this.resetGuidedGame({ announce: false })
    this.setGuidedPauseUi(this.guidedUserPaused)
    this.announceGuided(interruptedRound ? `Card ${this.guidedIndex + 1} of ${this.guidedCardTargets.length}. The previous round was canceled when you changed cards; choose a mode and start again.` : `Card ${this.guidedIndex + 1} of ${this.guidedCardTargets.length}. Choose a mode and start the round.`)
  }

  renderGuidedCard({ focus = false, persist = true } = {}) {
    this.guidedCardTargets.forEach((card, index) => {
      card.hidden = index !== this.guidedIndex
      card.setAttribute("aria-hidden", index === this.guidedIndex ? "false" : "true")
    })
    if (this.hasGuidedProgressTarget) {
      this.guidedProgressTarget.textContent = `Card ${this.guidedIndex + 1} of ${this.guidedCardTargets.length}`
    }
    if (this.hasGuidedPreviousTarget) this.guidedPreviousTarget.disabled = this.guidedIndex <= 0
    if (this.hasGuidedNextTarget) this.guidedNextTarget.disabled = this.guidedIndex >= this.guidedCardTargets.length - 1
    this.element.querySelectorAll("[data-guided-outline-link]").forEach((link) => {
      link.href = `#guided-${link.dataset.guidedOutlineLink}-${this.guidedIndex}`
    })
    this.updateGuidedRatingUi()
    if (persist) this.saveGuidedProgress()
    if (focus && this.hasGuidedBoardTarget) this.guidedBoardTarget.focus()
  }

  toggleGuidedPause() {
    if (this.guidedValue && this.expired) return

    const wasPaused = this.guidedUserPaused || this.guidedReadingPaused
    this.guidedUserPaused = !wasPaused
    this.guidedReadingPaused = false
    this.toggleGuidedGameClock(this.guidedUserPaused)
    this.setGuidedPauseUi(this.guidedUserPaused)
    this.announceGuided(this.guidedUserPaused ? "Paused. Resume when you are ready to continue." : "Resumed. Read and rehearse the current card aloud.")
  }

  pauseForReading() {
    if (!this.guidedValue || this.guidedUserPaused) return
    this.guidedReadingPaused = true
    this.toggleGuidedGameClock(true)
    this.setGuidedPauseUi(true)
  }

  resumeAfterReading(event) {
    if (!this.guidedValue || this.guidedUserPaused) return
    if (event.relatedTarget && event.currentTarget.contains(event.relatedTarget)) return
    this.guidedReadingPaused = false
    this.toggleGuidedGameClock(false)
    this.setGuidedPauseUi(false)
  }

  setGuidedPauseUi(paused) {
    if (this.hasGuidedPauseTarget) {
      this.guidedPauseTarget.textContent = this.expired ? "Session ended" : (paused ? "Resume" : "Pause")
      this.guidedPauseTarget.setAttribute("aria-pressed", this.expired ? "false" : (paused ? "true" : "false"))
      this.guidedPauseTarget.disabled = this.expired
    }
    this.currentGuidedGameStage()?.classList.toggle("is-paused", paused)
  }

  selectGuidedGameMode(event) {
    const mode = event.currentTarget.dataset.guidedGameMode
    if (!["best_answer", "completion"].includes(mode)) return

    if (this.expired) {
      this.announceGuided("Study time is complete. Gameplay is locked; the dossier remains available.")
      return
    }

    if (this.currentGuidedGameStage()?.dataset.gameState === "running") {
      this.setGuidedGameStatus("Finish the current round or use Restart round before changing modes.")
      this.announceGuided("Finish the current round or use Restart round before changing modes.")
      return
    }

    this.guidedGameMode = mode
    this.resetGuidedGame({ announce: false })
    const game = event.currentTarget.closest("[data-guided-game-card]")
    game?.querySelectorAll("[data-guided-game-mode]").forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.guidedGameMode === mode ? "true" : "false")
    })
    game?.querySelectorAll("[data-guided-game-prompt]").forEach((prompt) => {
      prompt.hidden = prompt.dataset.guidedGamePrompt !== mode
    })
    game?.querySelectorAll("[data-guided-game-options]").forEach((group) => {
      group.hidden = group.dataset.guidedGameOptions !== mode
    })
    this.setGuidedGameStatus(mode === "completion" ? "Sentence completion selected. Press Start round." : "Best-answer recognition selected. Press Start round.")
  }

  startGuidedGame(event) {
    const game = event.currentTarget.closest("[data-guided-game-card]")
    const stage = game?.querySelector("[data-guided-game-stage]")
    if (!game || !stage) return
    if (this.expired) {
      this.setGuidedGameStatus("Study time is complete. Gameplay is locked; the dossier remains available.", game)
      this.announceGuided("Study time is complete. Gameplay is locked; the dossier remains available.")
      return
    }

    this.closeGuidedLearningDialogs()
    this.resetGuidedGame({ announce: false })
    this.guidedUserPaused = false
    this.guidedReadingPaused = false
    this.setGuidedPauseUi(false)
    stage.dataset.gameState = "running"
    const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    stage.classList.toggle("is-static-round", Boolean(reducedMotion))
    const difficulty = this.guidedGameDifficulty()
    const options = this.guidedGameOptions(game)
    options.forEach((button) => {
      button.hidden = false
      button.disabled = false
      button.classList.remove("is-correct", "is-wrong")
      button.setAttribute("aria-pressed", "false")
      button.style.setProperty("--duration", `${difficulty.fallDurationMs}ms`)
      button.style.setProperty("--delay", `${difficulty.staggerMs * Number(button.dataset.guidedGameIndex || 0)}ms`)
      button.style.animation = "none"
      void button.offsetWidth
      button.style.animation = ""
    })
    this.setGuidedGameDifficultyUi(game, difficulty)
    event.currentTarget.textContent = "Restart round"
    this.setGuidedGameStatus(reducedMotion ? `Reduced motion is active. Choose from the static phrase list within ${this.formatGuidedGameSeconds(difficulty.deadlineMs)}.` : `Phrases are falling. Click one, or use keys 1–4 within ${this.formatGuidedGameSeconds(difficulty.deadlineMs)}.`, game)
    this.announceGuided("Round started. Choose the strongest falling phrase.")
    this.scheduleGuidedGameExpiry(game, difficulty.deadlineMs)
  }

  selectGuidedGameOption(event) {
    this.finishGuidedGameChoice(event.currentTarget)
  }

  nextGuidedGameRound(event) {
    if (this.expired) return

    const stage = this.currentGuidedGameStage()
    if (!stage || !["correct", "wrong", "timeout"].includes(stage.dataset.gameState)) return

    this.closeGuidedLearningDialogs()
    const nextIndex = (this.guidedIndex + 1) % this.guidedCardTargets.length
    this.setGuidedIndex(nextIndex, { focus: false })
    const nextStart = this.currentGuidedCard()?.querySelector("[data-guided-game-start]")
    if (nextStart) {
      this.startGuidedGame({ currentTarget: nextStart })
    }
    event.preventDefault()
  }

  finishGuidedGameChoice(option) {
    if (this.expired) return

    const game = option.closest("[data-guided-game-card]")
    const stage = game?.querySelector("[data-guided-game-stage]")
    if (!game || !stage || stage.dataset.gameState !== "running") return

    this.clearGuidedGameClock()
    const correct = option.dataset.guidedGameCorrect === "true"
    this.guidedGameRounds += 1
    if (correct) {
      this.guidedGameCorrect += 1
      this.guidedGameStreak += 1
      this.guidedGameScore += 100 * this.guidedGameLevel
    } else {
      this.guidedGameStreak = 0
    }
    this.guidedGameLevel = this.guidedGameLevelForRounds(this.guidedGameRounds)
    stage.dataset.gameState = correct ? "correct" : "wrong"
    stage.dataset.gameOutcome = correct ? "correct" : "wrong"
    this.guidedGameOptions(game).forEach((button) => {
      button.style.animationPlayState = "paused"
      button.disabled = true
      button.classList.toggle("is-correct", button.dataset.guidedGameCorrect === "true")
    })
    if (!correct) option.classList.add("is-wrong")
    this.setGuidedGameDifficultyUi(game, this.guidedGameDifficulty())
    const message = correct ? `Correct phrase. Rehearse the highlighted model answer aloud. Next round: level ${this.guidedGameLevel}, ${this.formatGuidedGameSeconds(this.guidedGameDifficulty().deadlineMs)}.` : `Not the authored best phrase. The correct option is highlighted in the learning review. Streak reset; next round is level ${this.guidedGameLevel}.`
    this.setGuidedGameStatus(message, game)
    this.setGuidedGameNextRoundLabel(game)
    this.announceGuided(message)
    this.openGuidedLearningDialog(game.closest("[data-guided-card-index]"))
  }

  expireGuidedGameRound(game) {
    if (this.expired) return

    const stage = game?.querySelector("[data-guided-game-stage]")
    if (!stage || stage.dataset.gameState !== "running") return

    this.clearGuidedGameClock()
    this.guidedGameRounds += 1
    this.guidedGameStreak = 0
    this.guidedGameLevel = this.guidedGameLevelForRounds(this.guidedGameRounds)
    stage.dataset.gameState = "timeout"
    stage.dataset.gameOutcome = "timeout"
    this.guidedGameOptions(game).forEach((button) => {
      button.style.animationPlayState = "paused"
      button.disabled = true
      button.classList.toggle("is-correct", button.dataset.guidedGameCorrect === "true")
    })
    this.setGuidedGameDifficultyUi(game, this.guidedGameDifficulty())
    const message = `Time is up. The authored answer is highlighted in the learning review. Streak reset; next round is level ${this.guidedGameLevel}.`
    this.setGuidedGameStatus(message, game)
    this.setGuidedGameNextRoundLabel(game)
    this.announceGuided(message)
    this.openGuidedLearningDialog(game.closest("[data-guided-card-index]"))
  }

  markGuidedGameExpired(game) {
    const stage = game?.querySelector("[data-guided-game-stage]")
    if (!game || !stage) return

    stage.dataset.gameState = "expired"
    stage.dataset.gameOutcome = "session_expired"
    stage.classList.remove("is-static-round")
    stage.classList.add("is-paused")
    game.querySelectorAll("[data-guided-game-mode], [data-guided-game-start], [data-guided-game-option]").forEach((control) => {
      control.disabled = true
    })
    const start = game.querySelector("[data-guided-game-start]")
    if (start) {
      start.textContent = "Session ended"
      start.dataset.action = ""
    }
    this.setGuidedGameStatus("Study time is complete. Gameplay is locked; the dossier remains available.", game)
  }

  resetGuidedGame({ announce = true } = {}) {
    this.clearGuidedGameClock()
    const card = this.currentGuidedCard()
    const game = card?.querySelector("[data-guided-game-card]")
    const stage = game?.querySelector("[data-guided-game-stage]")
    if (!game || !stage) return

    if (this.expired) {
      this.markGuidedGameExpired(game)
      return
    }

    stage.dataset.gameState = "idle"
    delete stage.dataset.gameOutcome
    stage.classList.remove("is-static-round", "is-paused")
    game.querySelectorAll("[data-guided-game-mode]").forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.guidedGameMode === this.guidedGameMode ? "true" : "false")
    })
    game.querySelectorAll("[data-guided-game-prompt]").forEach((prompt) => {
      prompt.hidden = prompt.dataset.guidedGamePrompt !== this.guidedGameMode
    })
    game.querySelectorAll("[data-guided-game-options]").forEach((group) => {
      group.hidden = group.dataset.guidedGameOptions !== this.guidedGameMode
    })
    game.querySelectorAll("[data-guided-game-option]").forEach((button) => {
      button.hidden = true
      button.disabled = false
      button.classList.remove("is-correct", "is-wrong")
      button.style.animation = ""
      button.style.animationPlayState = ""
      button.style.removeProperty("--duration")
      button.style.removeProperty("--delay")
      button.setAttribute("aria-pressed", "false")
    })
    const start = game.querySelector("[data-guided-game-start]")
    if (start) {
      start.textContent = "Start round"
      start.dataset.action = "click->english-arcade#startGuidedGame"
    }
    this.setGuidedGameDifficultyUi(game, this.guidedGameDifficulty())
    if (announce) this.setGuidedGameStatus("Choose a mode, then press Start round.", game)
  }

  currentGuidedCard() {
    return this.guidedCardTargets[this.guidedIndex]
  }

  currentGuidedGameStage() {
    return this.currentGuidedCard()?.querySelector("[data-guided-game-stage]")
  }

  guidedGameOptions(game = this.currentGuidedCard()?.querySelector("[data-guided-game-card]")) {
    const group = game?.querySelector(`[data-guided-game-options='${this.guidedGameMode}']`)
    return group ? Array.from(group.querySelectorAll("[data-guided-game-option]")) : []
  }

  runningGuidedGameOptions() {
    if (this.expired) return []

    const stage = this.currentGuidedGameStage()
    return stage?.dataset.gameState === "running" ? this.guidedGameOptions() : []
  }

  setGuidedGameStatus(message, game = this.currentGuidedCard()?.querySelector("[data-guided-game-card]")) {
    const status = game?.querySelector("[data-guided-game-status]")
    if (status) status.textContent = message
  }

  scheduleGuidedGameExpiry(game, durationMs) {
    this.clearGuidedGameClock()
    this.guidedGameRemainingMs = durationMs
    this.guidedGameEndsAt = performance.now() + durationMs
    this.guidedGameTimeout = window.setTimeout(() => this.expireGuidedGameRound(game), durationMs)
    this.guidedGameClock = window.setInterval(() => {
      const stage = game?.querySelector("[data-guided-game-stage]")
      if (!stage || stage.dataset.gameState !== "running" || this.guidedUserPaused || this.guidedReadingPaused) return

      this.guidedGameRemainingMs = Math.max(0, (this.guidedGameEndsAt || performance.now()) - performance.now())
      this.setGuidedGameDeadlineUi(game, this.guidedGameRemainingMs)
    }, GUIDED_GAME_CLOCK_INTERVAL_MS)
  }

  toggleGuidedGameClock(paused) {
    const stage = this.currentGuidedGameStage()
    if (!stage || stage.dataset.gameState !== "running") return

    if (paused) {
      if (!this.guidedGameEndsAt) return

      this.guidedGameRemainingMs = Math.max(0, (this.guidedGameEndsAt || performance.now()) - performance.now())
      if (this.guidedGameTimeout) window.clearTimeout(this.guidedGameTimeout)
      if (this.guidedGameClock) window.clearInterval(this.guidedGameClock)
      this.guidedGameTimeout = null
      this.guidedGameClock = null
      this.guidedGameEndsAt = null
    } else {
      const game = this.currentGuidedCard()?.querySelector("[data-guided-game-card]")
      this.scheduleGuidedGameExpiry(game, this.guidedGameRemainingMs || 1)
    }
  }

  clearGuidedGameClock() {
    if (this.guidedGameTimeout) window.clearTimeout(this.guidedGameTimeout)
    if (this.guidedGameClock) window.clearInterval(this.guidedGameClock)
    this.guidedGameTimeout = null
    this.guidedGameClock = null
    this.guidedGameRemainingMs = null
    this.guidedGameEndsAt = null
  }

  guidedGameLevelForRounds(rounds) {
    return Math.min(GUIDED_GAME_MAX_LEVEL, Math.max(1, rounds + 1))
  }

  guidedGameDifficulty() {
    const levelOffset = this.guidedGameLevel - 1
    const fallDurationMs = Math.max(GUIDED_GAME_MIN_FALL_MS, GUIDED_GAME_INITIAL_FALL_MS - (levelOffset * GUIDED_GAME_FALL_STEP_MS))
    const staggerMs = Math.max(GUIDED_GAME_MIN_STAGGER_MS, GUIDED_GAME_INITIAL_STAGGER_MS - (levelOffset * GUIDED_GAME_STAGGER_STEP_MS))
    const deadlineMs = Math.max(GUIDED_GAME_MIN_DEADLINE_MS, fallDurationMs + (3 * staggerMs) + GUIDED_GAME_DEADLINE_BUFFER_MS)
    return {
      level: this.guidedGameLevel,
      fallDurationMs,
      staggerMs,
      deadlineMs,
      speed: GUIDED_GAME_INITIAL_FALL_MS / fallDurationMs
    }
  }

  formatGuidedGameSeconds(milliseconds) {
    return `${(Math.max(0, milliseconds) / 1000).toFixed(1)} seconds`
  }

  setGuidedGameDifficultyUi(game, difficulty = this.guidedGameDifficulty()) {
    if (!game) return

    const stage = game.querySelector("[data-guided-game-stage]")
    if (stage) {
      stage.dataset.gameLevel = String(difficulty.level)
      stage.dataset.gameFallDurationMs = String(difficulty.fallDurationMs)
      stage.dataset.gameStaggerMs = String(difficulty.staggerMs)
      stage.dataset.gameDeadlineMs = String(difficulty.deadlineMs)
      stage.dataset.gameSpeed = difficulty.speed.toFixed(2)
    }
    const score = game.querySelector("[data-guided-game-score]")
    const streak = game.querySelector("[data-guided-game-streak]")
    const level = game.querySelector("[data-guided-game-level]")
    const speed = game.querySelector("[data-guided-game-speed]")
    const rounds = game.querySelector("[data-guided-game-rounds]")
    if (score) score.textContent = `Score ${this.guidedGameScore}`
    if (streak) streak.textContent = `Streak ${this.guidedGameStreak}`
    if (level) level.textContent = `Level ${difficulty.level}`
    if (speed) speed.textContent = `Speed ${difficulty.speed.toFixed(1)}×`
    if (rounds) rounds.textContent = `${this.guidedGameRounds} rounds · ${this.guidedGameCorrect} correct`
    this.setGuidedGameDeadlineUi(game, this.guidedGameRemainingMs)
  }

  setGuidedGameDeadlineUi(game, remainingMs = null) {
    const deadline = game?.querySelector("[data-guided-game-deadline]")
    if (!deadline) return

    const duration = remainingMs == null ? this.guidedGameDifficulty().deadlineMs : remainingMs
    deadline.textContent = `Deadline ${this.formatGuidedGameSeconds(duration)}`
  }

  setGuidedGameNextRoundLabel(game) {
    const start = game?.querySelector("[data-guided-game-start]")
    if (start) {
      start.textContent = "Next round"
      start.dataset.action = "click->english-arcade#nextGuidedGameRound"
    }
  }

  rateGuidedCard(event) {
    const rating = event.currentTarget.dataset.guidedRating
    if (!["review_again", "almost", "ready"].includes(rating)) return

    const card = this.guidedCardTargets[this.guidedIndex]
    const key = card?.dataset.guidedCardKey
    if (!key) return

    this.guidedRatings[key] = rating
    this.saveGuidedProgress()
    this.updateGuidedRatingUi()
    const label = { review_again: "Review again", almost: "Almost", ready: "Ready" }[rating]
    if (this.hasGuidedRatingStatusTarget) this.guidedRatingStatusTarget.textContent = `${label} saved locally for this card.`
    this.announceGuided(`${label} saved locally. Continue rehearsing or move to the next card.`)
  }

  updateGuidedRatingUi() {
    const key = this.guidedCardTargets[this.guidedIndex]?.dataset.guidedCardKey
    const rating = key ? this.guidedRatings[key] : null
    this.element.querySelectorAll("[data-guided-rating]").forEach((button) => {
      const selected = button.dataset.guidedRating === rating
      button.classList.toggle("is-selected", selected)
      button.setAttribute("aria-pressed", selected ? "true" : "false")
    })
    if (this.hasGuidedRatingStatusTarget) {
      const label = { review_again: "Review again", almost: "Almost", ready: "Ready" }[rating]
      this.guidedRatingStatusTarget.textContent = label ? `${label} saved locally for this card.` : "Saved only in this browser for guided review."
    }
  }

  readGuidedProgress() {
    const empty = { currentIndex: 0, ratings: {} }
    try {
      const raw = window.localStorage.getItem(this.guidedStorageKey())
      if (!raw) return empty
      const parsed = JSON.parse(raw)
      const ratings = parsed?.ratings && typeof parsed.ratings === "object" ? parsed.ratings : {}
      const safeRatings = Object.entries(ratings).reduce((result, [key, value]) => {
        if (["review_again", "almost", "ready"].includes(value)) result[key] = value
        return result
      }, {})
      const currentIndex = Number.isInteger(parsed?.currentIndex) ? parsed.currentIndex : 0
      return { currentIndex, ratings: safeRatings }
    } catch (_error) {
      return empty
    }
  }

  saveGuidedProgress() {
    if (!this.guidedValue) return
    try {
      window.localStorage.setItem(this.guidedStorageKey(), JSON.stringify({
        currentIndex: this.guidedIndex,
        ratings: this.guidedRatings
      }))
    } catch (_error) {
      // Private browsing or a restrictive browser may disable localStorage.
      // Guided reading remains fully usable without local persistence.
    }
  }

  guidedStorageKey() {
    const sessionKey = this.sessionKeyValue || "landing"
    return `english-arcade:guided:${sessionKey}`
  }

  announceGuided(message) {
    if (this.hasGuidedStatusTarget) this.guidedStatusTarget.textContent = message
  }

  submit(event) {
    if (!this.hasFormTarget) return
    const choice = this.formTarget.querySelector("input[name*='answer_choice']:checked")
    const submitter = event.submitter
    const skipping = submitter?.dataset.skip === "true" || submitter?.value === "skip"
    if (!choice && !skipping) {
      event.preventDefault()
      this.announce("Choose an answer before committing.")
      this.choiceTargets[0]?.focus()
      return
    }

    if (this.hasResponseMsTarget) {
      this.responseMsTarget.value = Math.max(1, Math.round(performance.now() - this.startedAt))
    }
    this.disableSubmits()
  }

  submitFeynman() {
    this.disableSubmits()
  }

  startCountdown() {
    if (!this.hasCountdownTarget || !this.activeValue || this.remainingSecondsValue <= 0) return

    this.renderCountdown()
    this.timer = window.setInterval(() => {
      if (this.guidedValue && (this.guidedUserPaused || this.guidedReadingPaused)) return
      this.remainingSecondsValue = Math.max(0, this.remainingSecondsValue - 1)
      this.renderCountdown()
      if (this.remainingSecondsValue === 0) this.expireSession()
    }, 1000)
  }

  renderCountdown() {
    const minutes = Math.floor(this.remainingSecondsValue / 60).toString().padStart(2, "0")
    const seconds = (this.remainingSecondsValue % 60).toString().padStart(2, "0")
    this.countdownTarget.textContent = `${minutes}:${seconds}`
    this.countdownTarget.classList.toggle("warn", this.remainingSecondsValue <= 60)
  }

  expireSession() {
    if (this.expired) return
    this.expired = true
    this.disableSubmits()
    if (this.guidedValue) {
      this.clearGuidedGameClock()
      this.guidedUserPaused = true
      this.guidedReadingPaused = false
      this.guidedCardTargets.forEach((card) => this.markGuidedGameExpired(card.querySelector("[data-guided-game-card]")))
      this.setGuidedPauseUi(true)
      this.announceGuided("Study time is complete. Gameplay is locked; the dossier remains available.")
      return
    }
    this.announce("Time is up. Your committed attempts are saved.")
    if (!this.finishUrlValue) return

    // The finish endpoint is POST-only; submit a tiny native form so timeout
    // follows the same CSRF and redirect path as the visible Finish button.
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.finishUrlValue
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "authenticity_token"
      input.value = token
      form.appendChild(input)
    }
    document.body.appendChild(form)
    HTMLFormElement.prototype.submit.call(form)
  }

  disableSubmits() {
    this.submitTargets.forEach((button) => { button.disabled = true })
  }

  announce(message) {
    if (this.guidedValue && this.hasGuidedStatusTarget) {
      this.announceGuided(message)
    } else if (this.hasFeedbackTarget) {
      this.feedbackTarget.setAttribute("aria-label", message)
    } else {
      this.element.setAttribute("aria-label", message)
    }
  }

}

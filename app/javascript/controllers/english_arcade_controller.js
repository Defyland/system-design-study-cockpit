import { Controller } from "@hotwired/stimulus"

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
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
    if (this.guidedValue) this.connectGuided()
    this.startCountdown()
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    if (this.timer) window.clearInterval(this.timer)
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
    this.announceGuided("Ready to practise aloud.")
  }

  handleGuidedKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (!this.hasGuidedCardTarget) return

    const activeTag = document.activeElement?.tagName
    if (["INPUT", "TEXTAREA", "SELECT"].includes(activeTag)) return

    if (/^[1-4]$/.test(event.key)) {
      this.chooseGuidedOption(Number(event.key) - 1)
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

    const nextIndex = Math.min(Math.max(index, 0), this.guidedCardTargets.length - 1)
    if (nextIndex === this.guidedIndex && this.guidedCardTargets[this.guidedIndex] && this.guidedCardTargets[this.guidedIndex].hidden === false) {
      return
    }

    this.guidedIndex = nextIndex
    this.renderGuidedCard({ focus, persist: true })
    this.guidedReadingPaused = false
    this.setGuidedPauseUi(this.guidedUserPaused)
    this.announceGuided(`Card ${this.guidedIndex + 1} of ${this.guidedCardTargets.length}. Ready to practise aloud.`)
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
    this.updateGuidedRatingUi()
    if (persist) this.saveGuidedProgress()
    if (focus && this.hasGuidedBoardTarget) this.guidedBoardTarget.focus()
  }

  toggleGuidedPause() {
    const wasPaused = this.guidedUserPaused || this.guidedReadingPaused
    this.guidedUserPaused = !wasPaused
    this.guidedReadingPaused = false
    this.setGuidedPauseUi(this.guidedUserPaused)
    this.announceGuided(this.guidedUserPaused ? "Paused. Resume when you are ready to continue." : "Resumed. Read and rehearse the current card aloud.")
  }

  pauseForReading() {
    if (!this.guidedValue || this.guidedUserPaused) return
    this.guidedReadingPaused = true
    this.setGuidedPauseUi(true)
  }

  resumeAfterReading(event) {
    if (!this.guidedValue || this.guidedUserPaused) return
    if (event.relatedTarget && event.currentTarget.contains(event.relatedTarget)) return
    this.guidedReadingPaused = false
    this.setGuidedPauseUi(false)
  }

  setGuidedPauseUi(paused) {
    if (!this.hasGuidedPauseTarget) return

    this.guidedPauseTarget.textContent = paused ? "Resume" : "Pause"
    this.guidedPauseTarget.setAttribute("aria-pressed", paused ? "true" : "false")
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
      this.guidedUserPaused = true
      this.setGuidedPauseUi(true)
      this.announceGuided("Study time is complete. The current card is paused for reading; no assessment was recorded.")
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

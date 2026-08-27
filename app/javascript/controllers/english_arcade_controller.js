import { Controller } from "@hotwired/stimulus"

// The controller owns interaction only. Grading, answer keys, feedback, and
// Leitner transitions stay on the server; a refresh cannot turn this into a
// client-side answer key.
export default class extends Controller {
  static targets = [
    "choice", "form", "submit", "responseMs", "typed", "countdown", "feedback"
  ]

  static values = {
    durationSeconds: Number,
    remainingSeconds: Number,
    active: Boolean,
    finishUrl: String
  }

  connect() {
    this.startedAt = performance.now()
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
    this.startCountdown()
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    if (this.timer) window.clearInterval(this.timer)
  }

  handleKeydown(event) {
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
    if (this.hasFeedbackTarget) {
      this.feedbackTarget.setAttribute("aria-label", message)
    } else {
      this.element.setAttribute("aria-label", message)
    }
  }

}

import { Controller } from "@hotwired/stimulus"

// Assessment interaction stays deliberately thin. The server owns answer keys,
// grading, feedback, and scheduling; this controller only handles keyboard
// affordances, countdowns, and the explicit authored-answer fill action.
export default class extends Controller {
  static targets = [
    "choice", "form", "submit", "responseMs", "typed", "countdown", "feedback"
  ]

  static values = {
    durationSeconds: Number,
    remainingSeconds: Number,
    active: Boolean,
    finishUrl: String,
    sessionKey: String
  }

  connect() {
    this.startedAt = performance.now()
    this.expired = Boolean(this.sessionKeyValue !== "landing" && !this.activeValue)
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
        // WebDriver and embedded browsers do not consistently dispatch
        // requestSubmit() from a label's synthetic Enter key. Native submit
        // keeps keyboard completion equivalent to the visible button.
        HTMLFormElement.prototype.submit.call(this.formTarget)
      }
    } else if (event.key === "Escape") {
      const first = this.formTarget.querySelector("input[name*='answer_choice']")
      first?.focus()
      event.preventDefault()
    }
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

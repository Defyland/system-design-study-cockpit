import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["advance", "button", "error"]

  connect() {
    this.busy = false
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "Lido, próximo →"
    }
  }

  touchStart(event) {
    this.start = event.touches.length === 1 && !window.getSelection()?.toString() && !event.target.closest("a, button, summary, input, select, pre, code, textarea")
      ? { x: event.touches[0].clientX, y: event.touches[0].clientY } : null
  }

  touchEnd(event) {
    if (!this.start || !this.hasAdvanceTarget || this.busy) return
    const end = event.changedTouches[0]
    const dx = end.clientX - this.start.x
    const dy = end.clientY - this.start.y
    this.start = null
    if (dx < -90 && Math.abs(dx) > Math.abs(dy) * 2 && !window.getSelection()?.toString()) this.advanceTarget.requestSubmit()
  }

  submitting(event) {
    if (this.busy) { event.preventDefault(); return }
    this.busy = true
    if (this.hasErrorTarget) this.errorTarget.hidden = true
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Salvando…"
    // Turbo restores controls after a failed request; allow retry as well.
    this.advanceTarget.addEventListener("turbo:submit-end", (result) => {
      this.busy = false
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "Lido, próximo →"
      if (!result.detail.success) this.failed()
    }, { once: true })
  }

  failed() {
    this.busy = false
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "Lido, próximo →"
    }
    if (this.hasErrorTarget) {
      this.errorTarget.hidden = false
      this.errorTarget.focus()
    }
  }

  retry() {
    if (!this.busy && this.hasAdvanceTarget) this.advanceTarget.requestSubmit()
  }
}

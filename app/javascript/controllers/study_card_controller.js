import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["advance", "button"]

  connect() {
    this.busy = false
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "Feito, próximo →"
    }
  }

  touchStart(event) {
    this.start = event.touches.length === 1 && !event.target.closest("a, button, summary, input, select, pre")
      ? { x: event.touches[0].clientX, y: event.touches[0].clientY } : null
  }

  touchEnd(event) {
    if (!this.start || !this.hasAdvanceTarget || this.busy) return
    const end = event.changedTouches[0]
    const dx = end.clientX - this.start.x
    const dy = end.clientY - this.start.y
    this.start = null
    if (dx < -90 && Math.abs(dx) > Math.abs(dy) * 2) this.advanceTarget.requestSubmit()
  }

  submitting(event) {
    if (this.busy) { event.preventDefault(); return }
    this.busy = true
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Salvando…"
    // Turbo restores controls after a failed request; allow retry as well.
    this.advanceTarget.addEventListener("turbo:submit-end", () => {
      this.busy = false
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "Feito, próximo →"
    }, { once: true })
  }
}

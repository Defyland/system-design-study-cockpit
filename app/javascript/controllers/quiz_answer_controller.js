import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "error"]

  connect() { this.busy = false; this.selected() }

  selected() {
    this.buttonTarget.disabled = this.busy || !this.element.querySelector('input[name="choice_id"]:checked')
  }

  submitting(event) {
    if (this.busy) { event.preventDefault(); return }
    this.busy = true
    this.errorTarget.hidden = true
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Salvando…"
    this.element.addEventListener("turbo:submit-end", (result) => {
      this.busy = false
      this.buttonTarget.textContent = "Conferir resposta"
      if (!result.detail.success) this.failed()
      this.selected()
    }, { once: true })
  }

  failed() {
    this.busy = false
    this.errorTarget.hidden = false
    this.buttonTarget.textContent = "Conferir resposta"
    this.selected()
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["required", "revealButton", "answer", "hint"]

  connect() {
    this.validate()
  }

  validate() {
    const textReady = this.requiredTargets.every((target) => target.value.trim().length > 0)
    const confidenceReady = this.element.querySelector("input[name='checkpoint_attempt[confidence]']:checked")
    const ready = textReady && confidenceReady

    this.revealButtonTarget.disabled = !ready
    this.hintTarget.hidden = ready
  }

  reveal() {
    this.validate()
    if (this.revealButtonTarget.disabled) return

    this.answerTarget.hidden = false
    this.revealButtonTarget.hidden = true
  }
}

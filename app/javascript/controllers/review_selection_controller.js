import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count", "button"]

  connect() { this.count() }

  count() {
    const count = this.element.querySelectorAll('input[name="card_keys[]"]:checked').length
    this.countTarget.textContent = count
    this.buttonTarget.disabled = count === 0
  }
}

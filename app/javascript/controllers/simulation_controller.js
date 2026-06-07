import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "value", "metric", "inputSnapshot", "decision", "feedback"]
  static values = { evaluateUrl: String }

  connect() {
    this.manualDecision = false
    this.abortController = null
    this.recalculate()
  }

  choose() {
    this.manualDecision = true
  }

  async recalculate() {
    const input = this.inputValues()

    this.valueTargets.forEach((target) => {
      const value = input[target.dataset.key]
      target.textContent = this.format(value)
    })

    this.inputSnapshotTarget.value = JSON.stringify(input)

    try {
      const output = await this.evaluate(input)
      this.applyOutput(output)
    } catch (error) {
      if (error.name !== "AbortError") throw error
    }
  }

  applyOutput(output) {
    this.metricTargets.forEach((target) => {
      const value = output[target.dataset.key]
      target.textContent = this.format(value)
      this.markDanger(target, value)
    })

    this.applyRecommendedDecision(output.recommendedDecision)
    this.applyFeedback(output.feedback)
  }

  inputValues() {
    return this.inputTargets.reduce((values, input) => {
      values[input.dataset.key] = Number.parseFloat(input.value)
      return values
    }, {})
  }

  async evaluate(input) {
    if (this.abortController) this.abortController.abort()

    this.abortController = new AbortController()
    const query = new URLSearchParams()

    Object.entries(input).forEach(([key, value]) => {
      query.append(`input_snapshot[${key}]`, value)
    })

    const response = await fetch(`${this.evaluateUrlValue}?${query}`, {
      headers: { Accept: "application/json" },
      signal: this.abortController.signal
    })

    if (!response.ok) throw new Error(`Simulation evaluation failed: ${response.status}`)

    const payload = await response.json()
    return payload.outputSnapshot
  }

  markDanger(target, value) {
    const card = target.closest(".metric-card")
    const dangerAt = Number.parseFloat(card.dataset.dangerAt)
    card.classList.toggle("danger", Number.isFinite(dangerAt) && Number.parseFloat(value) >= dangerAt)
  }

  applyRecommendedDecision(decision) {
    if (this.manualDecision || !decision) return

    const target = this.decisionTargets.find((radio) => radio.value === decision)
    if (target) target.checked = true
  }

  applyFeedback(feedback) {
    if (!this.hasFeedbackTarget || this.feedbackTarget.value.trim().length > 0) return

    this.feedbackTarget.value = feedback || ""
  }

  format(value) {
    if (typeof value === "string") return value
    if (!Number.isFinite(value)) return "--"
    if (Math.abs(value) >= 1000) return Math.round(value).toLocaleString("pt-BR")
    if (value % 1 === 0) return value.toString()

    return value.toFixed(1)
  }
}

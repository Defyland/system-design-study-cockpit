import { Controller } from "@hotwired/stimulus"

const WORDS = ["duck", "window", "coffee", "bridge", "garden", "bicycle", "ocean", "notebook"]
const REFLECTION_SUGGESTIONS = [
  "Relevance: answer the interview question directly before adding details.",
  "Main point: choose one problem, your action, and an outcome you can support.",
  "After a pause: take a breath, then restart with one simple sentence."
]

export default class extends Controller {
  static targets = ["step", "heading", "progress", "word", "association", "choice", "response", "aloud", "reflection", "suggestions", "error"]

  connect() {
    this.wordTarget.textContent = WORDS[0]
    this.remainingWords = WORDS.slice(1)
    this.resetAnswers()
    this.showStep(0, false)
  }

  next() {
    this.clearError()
    if (this.step === 0) {
      const associations = this.associationTargets.map((input) => input.value.trim())
      const invalidIndex = associations.findIndex((value, index) => !value || associations.slice(0, index).some((earlier) => earlier.toLowerCase() === value.toLowerCase()))
      if (invalidIndex !== -1) {
        this.showError("Enter three different associations. Each needs at least one non-space character.", this.associationTargets[invalidIndex])
        return
      }
      this.updateChoices(associations)
    } else if (this.step < 4) {
      const index = this.step - 1
      if (this.step === 1 && !this.choiceTarget.value) {
        this.showError("Choose one of your associations before continuing.", this.choiceTarget)
        return
      }
      if (!this.responseTargets[index].value.trim() && !this.aloudTargets[index].checked) {
        this.showError("Write a response or check ‘I answered aloud’ before continuing.", this.responseTargets[index])
        return
      }
    }
    this.showStep(Math.min(this.step + 1, 4))
  }

  back() {
    this.showStep(Math.max(this.step - 1, 0))
  }

  changeWord() {
    const currentWord = this.wordTarget.textContent
    if (this.remainingWords.length === 0) this.remainingWords = WORDS.filter((word) => word !== currentWord)
    const index = Math.floor(Math.random() * this.remainingWords.length)
    this.wordTarget.textContent = this.remainingWords.splice(index, 1)[0]
    this.resetAnswers()
    this.showStep(0)
  }

  changeAssociation() {
    this.responseTargets[0].value = ""
    this.aloudTargets[0].checked = false
    this.clearError()
  }

  retryInterview() {
    this.aloudTargets.slice(1).forEach((input) => { input.checked = false })
    this.reflectionTargets.forEach((input) => { input.checked = false })
    this.showStep(2)
  }

  reflect() {
    const suggestions = REFLECTION_SUGGESTIONS.filter((_, index) => !this.reflectionTargets[index].checked)
    if (suggestions.length === 0) suggestions.push("You marked all three observations. Try the interview answer again with fewer details, or take your next step into interview rehearsal.")
    this.suggestionsTarget.replaceChildren(...suggestions.map((suggestion) => {
      const item = document.createElement("li")
      item.textContent = suggestion
      return item
    }))
  }

  updateChoices(associations) {
    const previous = this.choiceTarget.value
    this.choiceTarget.replaceChildren(new Option("Select an association", ""), ...associations.map((value) => new Option(value, value)))
    this.choiceTarget.value = associations.find((value) => value.toLowerCase() === previous.toLowerCase()) || ""
    if (previous && !this.choiceTarget.value) this.changeAssociation()
  }

  resetAnswers() {
    this.associationTargets.forEach((input) => { input.value = "" })
    this.responseTargets.forEach((input) => { input.value = "" })
    this.aloudTargets.forEach((input) => { input.checked = false })
    this.reflectionTargets.forEach((input) => { input.checked = false })
    this.choiceTarget.replaceChildren(new Option("Select an association", ""))
    this.reflect()
  }

  showStep(step, focus = true) {
    this.step = step
    this.stepTargets.forEach((section, index) => { section.hidden = index !== step })
    this.progressTarget.textContent = step === 4 ? "Reflection · Four practice steps complete" : `Step ${step + 1} of 4`
    this.clearError()
    if (step === 4) this.reflect()
    if (focus) this.headingTargets[step].focus()
  }

  showError(message, input) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
    input.setAttribute("aria-invalid", "true")
    input.focus()
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
    this.element.querySelectorAll("[aria-invalid]").forEach((input) => input.removeAttribute("aria-invalid"))
  }
}

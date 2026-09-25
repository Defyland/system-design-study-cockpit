import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "row", "count", "choose", "hint", "empty"]

  connect() { this.count() }

  search() {
    const query = this.searchTarget.value.trim().toLocaleLowerCase()
    this.rowTargets.forEach((row) => {
      row.hidden = !row.textContent.toLocaleLowerCase().includes(query)
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = this.rowTargets.some((row) => !row.hidden)
  }

  count() {
    const selected = this.element.querySelectorAll('input[name="source_ids[]"]:checked').length
    this.countTarget.textContent = `${selected} selecionado${selected === 1 ? "" : "s"}`
    if (this.hasChooseTarget) this.chooseTarget.disabled = selected === 0
    if (this.hasHintTarget) this.hintTarget.hidden = selected > 0
  }

  choose() {
    const ids = [...this.element.querySelectorAll('input[name="source_ids[]"]:checked')].map((input) => input.value)
    if (ids.length === 0) return
    const params = new URLSearchParams({ topic: this.element.querySelector('input[name="topic"]').value })
    ids.forEach((id) => params.append('source_ids[]', id))
    window.location.assign(`/study-cards/configure?${params}`)
  }
}

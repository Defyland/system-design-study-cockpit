import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "item", "panel", "empty"]

  filter() {
    const query = this.normalize(this.queryTarget.value)

    this.itemTargets.forEach((item) => {
      const matches = query.length === 0 || this.normalize(item.textContent).includes(query)
      item.hidden = !matches
      if (!matches) item.open = false
    })

    this.panelTargets.forEach((panel) => {
      const hasVisibleItems = this.itemTargets.some((item) => panel.contains(item) && !item.hidden)
      const empty = panel.querySelector("[data-story-bank-filter-target~='empty']")
      if (empty) empty.hidden = hasVisibleItems
    })
  }

  normalize(value) {
    return value
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .trim()
  }
}

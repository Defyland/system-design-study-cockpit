import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { progressUrl: String }

  connect() {
    this.refresh()
  }

  async refresh() {
    if (!this.hasProgressUrlValue) return
    try {
      const response = await fetch(this.progressUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) return
      const progress = await response.json()
      this.updateMetrics(progress)
    } catch (_error) {
      // The server-rendered hub is a complete fallback when a refresh is offline.
    }
  }

  updateMetrics(progress) {
    const due = progress.due || {}
    const retention = progress.retention || {}
    const values = {
      streak: progress.streak_days ?? 0,
      due: due.total ?? 0,
      minutes: progress.minutes_today ?? 0,
      retention: `${Math.round(Number(retention.predicted_now || 0) * 100)}%`
    }
    Object.entries(values).forEach(([name, value]) => { const node = this.element.querySelector(`[data-arena-metric='${name}']`); if (node) node.textContent = value })
  }
}

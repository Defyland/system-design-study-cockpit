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
      this.updateTopConfusions(progress)
      this.updateCalibration(progress)
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

  updateTopConfusions(progress) {
    const list = this.element.querySelector("[data-arena-top-confusions]")
    if (!list) return
    list.replaceChildren()
    const rows = Array.isArray(progress.top_confusions_30d) ? progress.top_confusions_30d : []
    if (rows.length === 0) {
      const empty = document.createElement("li")
      empty.textContent = "No recorded confusions yet."
      list.append(empty)
      return
    }
    rows.forEach((row) => {
      const item = document.createElement("li")
      const axis = String(row.axis || "content").replaceAll("_", " ")
      const selected = String(row.selected || "(blank)")
      const count = Number(row.count || 0)
      item.textContent = `${axis} · ${selected} · ${count} recorded`
      list.append(item)
    })
  }

  updateCalibration(progress) {
    const container = this.element.querySelector("[data-arena-calibration]")
    if (!container) return
    container.replaceChildren()
    const calibration = progress.calibration_30d || {}
    const ratedEvents = Number(calibration.rated_events || 0)
    if (ratedEvents === 0) {
      const empty = document.createElement("p")
      empty.className = "arena-muted"
      empty.textContent = "No self-rated answers yet."
      container.append(empty)
      return
    }

    const list = document.createElement("dl")
    list.className = "arena-definition-list"
    Object.entries(calibration.by_rating || {}).filter(([, metric]) => Number(metric.events || 0) > 0).forEach(([rating, metric]) => {
      const row = document.createElement("div")
      const label = document.createElement("dt")
      label.textContent = `Self-rated ${rating}/4`
      const value = document.createElement("dd")
      const accuracy = Math.round(Number(metric.accuracy || 0) * 100)
      value.textContent = `${accuracy}% correct `
      const count = document.createElement("small")
      count.textContent = `(${Number(metric.events || 0)})`
      value.append(count)
      row.append(label, value)
      list.append(row)
    })
    container.append(list)
  }
}

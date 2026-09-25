import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "list", "transform", "mapButton", "listButton", "zoomControls"]

  connect() {
    this.scale = 1
    this.mode = window.matchMedia("(max-width: 680px)").matches ? "list" : "map"
    this.render()
  }

  map() { this.mode = "map"; this.render() }
  list() { this.mode = "list"; this.render() }
  zoomIn() { this.scale = Math.min(1.8, this.scale + .2); this.render() }
  zoomOut() { this.scale = Math.max(.6, this.scale - .2); this.render() }
  fit() { this.scale = 1; this.render(); this.canvasTarget.scrollTo(0, 0) }

  render() {
    const isMap = this.mode === "map"
    this.canvasTarget.hidden = !isMap
    this.listTarget.hidden = isMap
    this.zoomControlsTarget.hidden = !isMap
    this.mapButtonTarget.setAttribute("aria-pressed", String(isMap))
    this.listButtonTarget.setAttribute("aria-pressed", String(!isMap))
    this.transformTarget.style.transform = `scale(${this.scale})`
    this.transformTarget.style.transformOrigin = "top left"
  }
}

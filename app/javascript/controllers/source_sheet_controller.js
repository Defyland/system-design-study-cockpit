import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.popstate = () => {
      if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
      requestAnimationFrame(() => this.focusOrigin())
    }
    window.addEventListener("popstate", this.popstate)
    const key = `${location.pathname}${location.search}`
    if (sessionStorage.getItem("study-source-restore-focus") === key) {
      sessionStorage.removeItem("study-source-restore-focus")
      requestAnimationFrame(() => this.focusOrigin())
    }
  }

  disconnect() { window.removeEventListener("popstate", this.popstate) }

  open(event) {
    this.opener = event.currentTarget
    this.dialogTarget.showModal()
    history.pushState({ studySource: true }, "", "#source")
    this.dialogTarget.querySelector('button[aria-label="Fechar fonte"]').focus()
  }

  close() { this.dialogTarget.close() }

  closed() {
    if (history.state?.studySource) {
      sessionStorage.setItem("study-source-restore-focus", `${location.pathname}${location.search}`)
      history.back()
    } else {
      this.focusOrigin()
    }
  }

  focusOrigin() {
    document.querySelector('button[data-action="click->source-sheet#open"]')?.focus({ preventScroll: true })
  }
}

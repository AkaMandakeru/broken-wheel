import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "overlay"]

  connect() {
    this.handleEscape = (e) => { if (e.key === "Escape") this.close() }
  }

  open() {
    document.body.classList.add("overflow-hidden")
    this.overlayTarget.classList.remove("hidden")
    this.panelTarget.classList.remove("-translate-x-full")
    document.addEventListener("keydown", this.handleEscape)
  }

  close() {
    document.body.classList.remove("overflow-hidden")
    this.panelTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
    document.removeEventListener("keydown", this.handleEscape)
  }

  toggle() {
    if (this.panelTarget.classList.contains("-translate-x-full")) {
      this.open()
    } else {
      this.close()
    }
  }
}

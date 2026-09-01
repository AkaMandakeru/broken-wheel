import { Controller } from "@hotwired/stimulus"

// Hides a banner as soon as it's dismissed, and records the dismissal in the
// background. The form works on its own without JavaScript — this only spares
// the user a full page reload.
export default class extends Controller {
  static targets = ["panel"]

  async dismiss(event) {
    const form = event.target.closest("form")
    if (!form) return

    event.preventDefault()
    this.hide()

    try {
      await fetch(form.action, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": form.querySelector("input[name=authenticity_token]")?.value || "",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })
    } catch (error) {
      // The banner is already gone for this page view; it will simply come back
      // on the next one if the dismissal never landed.
      console.error(error)
    }
  }

  hide() {
    const panel = this.hasPanelTarget ? this.panelTarget : this.element
    panel.style.transition = "opacity 200ms ease, transform 200ms ease"
    panel.style.opacity = "0"
    panel.style.transform = "translateY(-6px)"
    setTimeout(() => this.element.remove(), 200)
  }
}

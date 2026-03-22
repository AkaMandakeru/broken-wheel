import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "overlay", "icon", "name", "title", "description", "points",
    "earnedSection", "earnedAt",
    "lockedSection", "progressBar", "progressBarSection", "progressLabel"
  ]

  open(event) {
    const card = event.currentTarget

    this.iconTarget.textContent        = card.dataset.badgeIcon
    this.nameTarget.textContent        = card.dataset.badgeName
    this.titleTarget.textContent       = card.dataset.badgeTitle
    this.descriptionTarget.textContent = card.dataset.badgeDescription
    this.pointsTarget.textContent      = card.dataset.badgePoints + " pts"

    if (card.dataset.badgeEarned === "true") {
      this.earnedSectionTarget.classList.remove("hidden")
      this.lockedSectionTarget.classList.add("hidden")
      this.earnedAtTarget.textContent = card.dataset.badgeEarnedAt
    } else {
      this.earnedSectionTarget.classList.add("hidden")
      this.lockedSectionTarget.classList.remove("hidden")

      const pct   = card.dataset.badgeProgressPct   || "0"
      const label = card.dataset.badgeProgressLabel || ""
      const kind  = card.dataset.badgeProgressKind  || "bar"

      this.progressLabelTarget.textContent   = label
      this.progressBarTarget.style.width     = pct + "%"

      // For pace badges, hide the bar (it's not intuitive) and just show the label
      if (kind === "pace") {
        this.progressBarSectionTarget.classList.add("hidden")
      } else {
        this.progressBarSectionTarget.classList.remove("hidden")
      }
    }

    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === this.overlayTarget) this.close()
  }
}

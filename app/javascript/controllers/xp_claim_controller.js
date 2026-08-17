import { Controller } from "@hotwired/stimulus"

// Collects the XP waiting on finished challenges, and shows it arriving.
//
// The claim itself is a normal form post — this controller intercepts it to do
// the same thing over fetch so the page doesn't reload and the XP can be
// animated into the bar. With JavaScript off, the forms still work on their own.
export default class extends Controller {
  static targets = ["panel", "list", "item", "xp", "level", "bar", "toNext"]

  // How long the orb takes to reach the counter, and how long the number then
  // takes to count up. Kept short: this sits between the player and their score.
  static FLIGHT_MS = 700
  static COUNT_MS = 600

  connect() {
    this.busy = false
  }

  claim(event) {
    this.submit(event, event.target.closest("[data-completion-id]"))
  }

  claimAll(event) {
    this.submit(event, null)
  }

  async submit(event, item) {
    const form = event.target.closest("form")
    if (!form) return

    event.preventDefault()
    if (this.busy) return
    this.busy = true

    const button = form.querySelector("button, input[type=submit]")
    this.setPending(button, true)

    try {
      const response = await fetch(form.action, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken(form),
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(`Claim failed: ${response.status}`)
      const result = await response.json()

      await this.celebrate(button, result, item)
    } catch (error) {
      // Fall back to a normal submit so the claim still lands.
      console.error(error)
      form.submit()
      return
    } finally {
      this.busy = false
      this.setPending(button, false)
    }
  }

  async celebrate(button, result, item) {
    if (result.xp_gained > 0) await this.flyToCounter(button, result.xp_gained)

    this.applyResult(result)
    this.removeClaimed(item)
  }

  // An orb of XP travelling from the button to the counter, so the number that
  // changes is visibly the one that was just collected.
  async flyToCounter(button, amount) {
    if (!this.hasXpTarget || this.reducedMotion) return

    const from = button.getBoundingClientRect()
    const to = this.xpTarget.getBoundingClientRect()

    const orb = document.createElement("div")
    orb.textContent = `+${amount.toLocaleString()} XP`
    orb.className =
      "pointer-events-none fixed z-[100] rounded-full bg-amber-500 px-3 py-1 text-xs font-bold text-white shadow-lg"
    orb.style.left = `${from.left + from.width / 2}px`
    orb.style.top = `${from.top + from.height / 2}px`
    orb.style.transform = "translate(-50%, -50%)"
    document.body.appendChild(orb)

    const dx = to.left + to.width / 2 - (from.left + from.width / 2)
    const dy = to.top + to.height / 2 - (from.top + from.height / 2)

    await this.play(orb, [
      { transform: "translate(-50%, -50%) scale(0.6)", opacity: 0 },
      { transform: "translate(-50%, -50%) scale(1.1)", opacity: 1, offset: 0.15 },
      { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) scale(0.5)`, opacity: 0 }
    ], this.constructor.FLIGHT_MS)

    orb.remove()
    this.pulse(this.xpTarget)
  }

  applyResult(result) {
    if (this.hasXpTarget) this.countTo(this.xpTarget, result.xp)
    if (this.hasBarTarget) this.barTarget.style.width = `${result.progress_percent}%`

    if (this.hasLevelTarget && result.level != null) {
      const changed = this.levelTarget.textContent.trim() !== String(result.level)
      this.levelTarget.textContent = result.level
      if (changed) this.pulse(this.levelTarget.parentElement)
    }

    if (this.hasToNextTarget && result.xp_to_next != null) {
      this.toNextTarget.textContent = this.toNextTarget.dataset.template
        ? this.toNextTarget.dataset.template.replace("%{xp}", result.xp_to_next.toLocaleString())
        : this.toNextTarget.textContent.replace(/[\d.,]+/, result.xp_to_next.toLocaleString())
    }
  }

  removeClaimed(item) {
    const items = item ? [item] : [...this.itemTargets]

    items.forEach((element) => {
      element.style.transition = "opacity 250ms ease, transform 250ms ease"
      element.style.opacity = "0"
      element.style.transform = "translateX(12px)"
      setTimeout(() => element.remove(), 250)
    })

    // Once the last one is collected the panel has nothing left to say.
    setTimeout(() => {
      if (this.itemTargets.length === 0 && this.hasPanelTarget) {
        this.panelTarget.style.transition = "opacity 300ms ease"
        this.panelTarget.style.opacity = "0"
        setTimeout(() => this.panelTarget.remove(), 300)
      }
    }, 300)
  }

  // --- helpers --------------------------------------------------------------

  countTo(element, target) {
    const start = this.numberFrom(element.textContent)
    if (this.reducedMotion || start === target) {
      element.textContent = target.toLocaleString()
      return
    }

    const started = performance.now()
    const step = (now) => {
      const progress = Math.min((now - started) / this.constructor.COUNT_MS, 1)
      // Ease out, so it lands softly rather than stopping dead.
      const eased = 1 - Math.pow(1 - progress, 3)
      element.textContent = Math.round(start + (target - start) * eased).toLocaleString()
      if (progress < 1) requestAnimationFrame(step)
    }
    requestAnimationFrame(step)
  }

  pulse(element) {
    if (!element || this.reducedMotion) return

    this.play(element, [
      { transform: "scale(1)" },
      { transform: "scale(1.18)" },
      { transform: "scale(1)" }
    ], 420)
  }

  // Web Animations API — no library needed, and resolves even where it is
  // unavailable so the flow never stalls waiting on an animation.
  play(element, keyframes, duration) {
    if (!element?.animate) return Promise.resolve()

    return element.animate(keyframes, { duration, easing: "cubic-bezier(0.22, 1, 0.36, 1)", fill: "forwards" })
      .finished.catch(() => {})
  }

  numberFrom(text) {
    return parseInt(String(text).replace(/[^\d]/g, ""), 10) || 0
  }

  setPending(button, pending) {
    if (!button) return
    button.disabled = pending
    button.classList.toggle("opacity-60", pending)
    button.classList.toggle("cursor-wait", pending)
  }

  csrfToken(form) {
    return (
      form.querySelector("input[name=authenticity_token]")?.value ||
      document.querySelector("meta[name=csrf-token]")?.content ||
      ""
    )
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}

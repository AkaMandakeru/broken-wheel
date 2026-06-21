import { Controller } from "@hotwired/stimulus"

// Manages the Web Push opt-in: registers the subscription with the server and
// reflects the current state on a toggle button.
export default class extends Controller {
  static targets = ["button", "status"]
  static values = {
    enableLabel: String,
    disableLabel: String,
    enabledStatus: String,
    disabledStatus: String,
    deniedStatus: String,
    unsupportedStatus: String
  }

  connect() {
    this.supported = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
    if (!this.supported) {
      this.disableButton(this.unsupportedStatusValue)
      return
    }
    this.refresh()
  }

  async refresh() {
    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()
      this.render(!!subscription)
    } catch (e) {
      this.disableButton(this.unsupportedStatusValue)
    }
  }

  async toggle() {
    const registration = await navigator.serviceWorker.ready
    const existing = await registration.pushManager.getSubscription()
    existing ? await this.disable(existing) : await this.enable(registration)
  }

  async enable(registration) {
    const permission = await Notification.requestPermission()
    if (permission !== "granted") {
      this.statusTarget.textContent = this.deniedStatusValue
      return
    }

    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.urlBase64ToUint8Array(this.vapidKey)
    })

    await this.request("POST", { subscription: subscription.toJSON() })
    this.render(true)
  }

  async disable(subscription) {
    await this.request("DELETE", { endpoint: subscription.endpoint })
    await subscription.unsubscribe()
    this.render(false)
  }

  // --- helpers ---

  render(enabled) {
    if (this.hasButtonTarget) this.buttonTarget.textContent = enabled ? this.disableLabelValue : this.enableLabelValue
    if (this.hasStatusTarget) this.statusTarget.textContent = enabled ? this.enabledStatusValue : this.disabledStatusValue
  }

  disableButton(message) {
    if (this.hasButtonTarget) this.buttonTarget.disabled = true
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  request(method, body) {
    return fetch("/push_subscription", {
      method,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken },
      body: JSON.stringify(body)
    })
  }

  get vapidKey() {
    return document.querySelector('meta[name="vapid-public-key"]')?.content
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(base64)
    return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)))
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "placeholder", "input", "container"]
  static values = { multiple: { type: Boolean, default: false } }

  connect() {
    this._urls = []
  }

  preview() {
    const files = this.inputTarget.files
    if (!files?.length) return

    if (this.multipleValue) {
      this.previewMultiple(files)
    } else {
      this.previewSingle(files[0])
    }
  }

  previewSingle(file) {
    if (!file?.type.startsWith("image/")) return

    this.revokeUrls()
    const url = URL.createObjectURL(file)
    this._urls.push(url)
    this.previewTarget.src = url
    this.previewTarget.classList.remove("hidden")
    this.element.querySelectorAll("[data-image-preview-target='placeholder'], [data-image-preview-target='current']").forEach((el) => {
      el.classList.add("hidden")
    })
  }

  previewMultiple(files) {
    if (!this.hasContainerTarget) return

    this.revokeUrls()
    this.containerTarget.innerHTML = ""
    Array.from(files).filter((f) => f.type.startsWith("image/")).forEach((file) => {
      const url = URL.createObjectURL(file)
      this._urls.push(url)
      const img = document.createElement("img")
      img.src = url
      img.className = "rounded-lg max-h-24 object-cover"
      this.containerTarget.appendChild(img)
    })
  }

  revokeUrls() {
    this._urls?.forEach((url) => URL.revokeObjectURL(url))
    this._urls = []
  }

  disconnect() {
    this.revokeUrls()
  }
}

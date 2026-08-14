import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String, copied: String }

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      const original = this.element.textContent
      this.element.textContent = this.copiedValue || "Copied"
      setTimeout(() => { this.element.textContent = original }, 1200)
    })
  }
}

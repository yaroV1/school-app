import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String, copied: String }

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      this.originalText ||= this.element.textContent
      this.element.textContent = this.copiedValue || "Copied"
      this.element.classList.add("is-copied")
      clearTimeout(this.resetTimer)
      this.resetTimer = setTimeout(() => {
        this.element.textContent = this.originalText
        this.element.classList.remove("is-copied")
      }, 1200)
    })
  }

  disconnect() {
    clearTimeout(this.resetTimer)
    if (!this.originalText) return

    this.element.textContent = this.originalText
    this.element.classList.remove("is-copied")
  }
}

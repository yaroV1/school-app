import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  static values = { text: String, copied: String }

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      this.originalText ||= this.labelElement.textContent
      this.labelElement.textContent = this.copiedValue || "Copied"
      this.element.classList.add("is-copied")
      clearTimeout(this.resetTimer)
      this.resetTimer = setTimeout(() => {
        this.labelElement.textContent = this.originalText
        this.element.classList.remove("is-copied")
      }, 1200)
    })
  }

  disconnect() {
    clearTimeout(this.resetTimer)
    if (!this.originalText) return

    this.labelElement.textContent = this.originalText
    this.element.classList.remove("is-copied")
  }

  // Swapping the whole element's textContent would erase the action icon that
  // now sits beside the label; the span target scopes the swap to the words.
  get labelElement() {
    return this.hasLabelTarget ? this.labelTarget : this.element
  }
}

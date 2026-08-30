import { Controller } from "@hotwired/stimulus"

// Pairs stay in hidden inputs named like the old selects, so autosave's FormData
// walk does not change. Left/right ids are the student-facing ones already on
// the page; the correct mapping is never written into data attributes.
export default class extends Controller {
  static targets = [ "left", "right", "input" ]

  connect() {
    this.selectedLeft = null
    this.paintPairs()
  }

  pickLeft(event) {
    const button = event.currentTarget
    if (this.selectedLeft === button) {
      this.clearLeftSelection()
      return
    }

    this.selectedLeft = button
    this.leftTargets.forEach((el) => {
      el.setAttribute("aria-selected", el === button ? "true" : "false")
    })
  }

  pickRight(event) {
    if (!this.selectedLeft) return

    const leftId = this.selectedLeft.dataset.id
    const rightId = event.currentTarget.dataset.id
    const input = this.inputTargets.find((el) => el.dataset.leftId === leftId)
    if (!input) return

    input.value = input.value === rightId ? "" : rightId
    this.paintPairs()
    this.clearLeftSelection()
    this.dispatch("changed")
  }

  clearLeftSelection() {
    this.selectedLeft = null
    this.leftTargets.forEach((el) => el.setAttribute("aria-selected", "false"))
  }

  paintPairs() {
    const taken = {}
    this.inputTargets.forEach((input) => {
      if (input.value) taken[input.dataset.leftId] = input.value
    })

    this.leftTargets.forEach((el) => {
      const rightId = taken[el.dataset.id]
      el.dataset.paired = rightId ? "true" : "false"
      const status = el.querySelector("[data-matching-pair]")
      if (!status) return

      const right = this.rightTargets.find((item) => item.dataset.id === rightId)
      status.textContent = right ? right.textContent.trim() : ""
    })

    this.rightTargets.forEach((el) => {
      el.dataset.paired = Object.values(taken).includes(el.dataset.id) ? "true" : "false"
    })
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "mark", "card" ]
  static values = {
    answered: { type: String, default: "" },
    empty: { type: String, default: "" }
  }

  connect() {
    this.refresh()
  }

  orderingChanged(event) {
    event.target.closest("[data-run-progress-target='card']")?.setAttribute("data-touched", "true")
    this.refresh()
  }

  refresh() {
    this.markTargets.forEach((mark, index) => {
      const card = this.cardTargets.find((el) => el.dataset.questionId === mark.dataset.questionId)
      const filled = card ? this.filled(card) : mark.dataset.answered === "true"
      mark.dataset.answered = filled ? "true" : "false"
      const template = filled ? this.answeredValue : this.emptyValue
      if (template) mark.setAttribute("aria-label", template.replace("%{n}", String(index + 1)))
    })
  }

  filled(card) {
    switch (card.dataset.qtype) {
      case "mcq":
        return Boolean(card.querySelector("input[type=radio]:checked"))
      case "ordering":
        return card.dataset.touched === "true" || card.dataset.answered === "true"
      case "matching":
        return [ ...card.querySelectorAll("[data-matching-target='input']") ].some((el) => el.value)
      default:
        return [ ...card.querySelectorAll("input[type=text], textarea") ].some((el) => el.value.trim())
    }
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "submit"]

  connect() {
    // Turbo snapshots the page as it leaves it, open dialog included, and the back
    // button would restore that snapshot as a panel stuck open outside the top layer.
    this.boundClose = () => this.close()
    document.addEventListener("turbo:before-cache", this.boundClose)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.boundClose)
  }

  open() {
    this.dialogTarget.showModal()
    this.refresh()
  }

  close() {
    this.dialogTarget.close()
  }

  // A tap on the backdrop lands on the <dialog> element itself; anything inside the
  // panel is a descendant, so this closes on the backdrop alone.
  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // The server repeats this check and answers an empty selection with a flash, so the
  // disabled button is only the faster answer: on a phone the button must stop looking
  // pressable the moment the last box is cleared.
  refresh() {
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = !this.dialogTarget.querySelector("input[type=checkbox]:checked")
  }
}

import { Controller } from "@hotwired/stimulus"

// Submits the form the controller sits on, so a select can apply immediately
// instead of waiting for the button.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}

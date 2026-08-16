import { Controller } from "@hotwired/stimulus"

// Uses server_time + deadline to avoid client clock skew affecting the display.
// Enforcement remains server-side on save/submit.
export default class extends Controller {
  static values = {
    deadline: String,
    serverTime: String
  }
  static targets = ["display"]

  connect() {
    const serverMs = Date.parse(this.serverTimeValue)
    this.offsetMs = Number.isNaN(serverMs) ? 0 : (serverMs - Date.now())
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  now() {
    return Date.now() + this.offsetMs
  }

  tick() {
    const deadline = Date.parse(this.deadlineValue)
    const remaining = Math.max(0, Math.floor((deadline - this.now()) / 1000))
    const m = Math.floor(remaining / 60)
    const s = remaining % 60
    this.displayTarget.textContent = `${m}:${String(s).padStart(2, "0")}`
    this.element.dataset.urgency = remaining <= 60 ? "urgent" : "normal"
    if (remaining === 0) {
      clearInterval(this.timer)
      this.element.dispatchEvent(new CustomEvent("countdown:ended", { bubbles: true }))
    }
  }
}

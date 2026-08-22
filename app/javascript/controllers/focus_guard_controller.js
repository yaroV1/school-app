import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    attemptId: Number,
    throttle: { type: Number, default: 1000 }
  }

  connect() {
    this.lastReportedAt = 0
    this.boundReport = () => {
      if (document.visibilityState === "hidden") this.report()
    }
    // visibilitychange only. `blur` also fires for dev tools and for focus moves inside the
    // window, which would count a student who never left the page.
    document.addEventListener("visibilitychange", this.boundReport)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundReport)
  }

  report() {
    // Some browsers fire visibilitychange twice for one switch, and the cap bounds the stored
    // value but not the request rate — a report that writes nothing still costs a request.
    const now = Date.now()
    if (now - this.lastReportedAt < this.throttleValue) return
    this.lastReportedAt = now

    const token = document.querySelector("meta[name='csrf-token']")?.content

    // keepalive, not sendBeacon: the tab is going away, and a beacon cannot carry the CSRF header.
    // The signal is advisory, so a failed report is dropped rather than shown to the student.
    fetch(this.urlValue, {
      method: "POST",
      keepalive: true,
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
        "Accept": "application/json"
      },
      body: JSON.stringify({ attempt_id: this.attemptIdValue })
    }).catch(() => {})
  }
}

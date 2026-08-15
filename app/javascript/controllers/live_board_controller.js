import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 4000 },
    src: String,
    toastOne: String,
    toastOther: String
  }

  connect() {
    this.knownSubmitted = new Set()
    this.ready = false
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
    this.observer = new MutationObserver(() => this.onBoardChange())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    clearInterval(this.timer)
    this.observer?.disconnect()
  }

  async refresh() {
    const frame = document.getElementById("live_board")
    if (!frame || !this.srcValue) return

    try {
      const response = await fetch(this.srcValue, {
        headers: { Accept: "text/vnd.turbo-stream.html, text/html", "Turbo-Frame": "live_board" }
      })
      const html = await response.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const next = doc.getElementById("live_board")
      if (next) frame.replaceWith(next)
    } catch (e) {
      // ignore transient network errors while polling
    }
  }

  onBoardChange() {
    if (!document.getElementById("live-board-data")) return

    if (!this.ready) {
      this.captureSubmitted()
      this.ready = true
      return
    }

    this.announceNewSubmits(this.knownSubmitted)
  }

  captureSubmitted() {
    this.knownSubmitted = this.currentSubmittedIds()
  }

  currentSubmittedIds() {
    const el = document.getElementById("live-board-data")
    if (!el) return new Set()
    const raw = el.dataset.submittedIds || ""
    return new Set(raw.split(",").filter(Boolean))
  }

  announceNewSubmits(previous) {
    const current = this.currentSubmittedIds()
    let added = 0
    current.forEach((id) => {
      if (!previous.has(id) && !this.knownSubmitted.has(id)) added += 1
    })
    this.knownSubmitted = current
    if (added === 0) return

    const toast = document.getElementById("live-toast")
    if (!toast) return
    toast.textContent = added === 1
      ? (this.toastOneValue || "New submission received")
      : (this.toastOtherValue || `${added} new submissions received`).replaceAll("__COUNT__", String(added))
    toast.classList.remove("hidden")
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => toast.classList.add("hidden"), 4000)
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 4000 },
    src: String,
    toastOne: String,
    toastOther: String
  }

  connect() {
    // Baseline now, so a board restored from Turbo's page cache does not treat
    // the next real submission as its starting point.
    this.knownSubmitted = this.currentSubmittedIds()

    // The board changes three ways: its first lazy load, a broadcast, and the
    // polling fallback below. Each one says so explicitly, rather than watching
    // the DOM and guessing which mutations were a submission.
    this.onFrameLoad = (event) => {
      if (event.target.id === "live_board") this.captureSubmitted()
    }
    // turbo:before-stream-render fires *before* the swap, and Turbo only awaits
    // its own repaint afterwards — a requestAnimationFrame queued from this
    // handler would run first and read the old board. Wrapping detail.render is
    // the supported way to act once the DOM is actually updated.
    this.onStreamRender = (event) => {
      if (event.target.getAttribute("target") !== "live_board") return

      const render = event.detail.render
      event.detail.render = async (streamElement) => {
        await render(streamElement)
        this.announceNewSubmits()
      }
    }
    document.addEventListener("turbo:frame-load", this.onFrameLoad)
    document.addEventListener("turbo:before-stream-render", this.onStreamRender)

    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
    clearTimeout(this.toastTimer)
    document.removeEventListener("turbo:frame-load", this.onFrameLoad)
    document.removeEventListener("turbo:before-stream-render", this.onStreamRender)
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
      if (!next || this.isStale(next)) return

      frame.replaceWith(next)
      this.announceNewSubmits()
    } catch (e) {
      // ignore transient network errors while polling
    }
  }

  // A poll can start before a broadcast and land after it. Applying that older
  // snapshot would roll the board back and re-announce the same submission.
  isStale(next) {
    const incoming = next.querySelector("#live-board-data")?.dataset.serverTime
    const shown = document.getElementById("live-board-data")?.dataset.serverTime
    if (!incoming || !shown) return false

    return Date.parse(incoming) < Date.parse(shown)
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

  announceNewSubmits() {
    const current = this.currentSubmittedIds()
    let added = 0
    current.forEach((id) => { if (!this.knownSubmitted.has(id)) added += 1 })
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

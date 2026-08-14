import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    attemptId: Number,
    lockVersion: Number,
    interval: { type: Number, default: 15000 },
    saving: { type: String, default: "Saving…" },
    saved: { type: String, default: "Saved" },
    failed: { type: String, default: "Save failed" }
  }
  static targets = ["status"]

  connect() {
    this.timer = setInterval(() => this.save(), this.intervalValue)
    document.addEventListener("visibilitychange", this.boundSave = () => {
      if (document.visibilityState === "hidden") this.save()
    })
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.boundSave)
  }

  collectAnswers() {
    const formData = new FormData(this.element)
    const byQuestion = {}

    for (const [key, value] of formData.entries()) {
      if (!key.startsWith("answers[")) continue
      const parts = [...key.matchAll(/\[([^\]]*)\]/g)].map((match) => match[1])
      if (parts.length < 2) continue

      const questionId = parts[0]
      const field = parts[1]
      byQuestion[questionId] ||= { question_id: questionId, payload: {} }
      const payload = byQuestion[questionId].payload

      if (field === "order") {
        payload.order ||= []
        payload.order.push(value)
      } else if (field === "pairs") {
        payload.pairs ||= {}
        payload.pairs[parts[2]] = value
      } else {
        payload[field] = value
      }
    }

    return Object.values(byQuestion)
  }

  async save() {
    const answers = this.collectAnswers()
    if (answers.length === 0) return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    this.setStatus(this.savingValue)

    try {
      const response = await fetch(this.urlValue, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          attempt_id: this.attemptIdValue,
          lock_version: this.lockVersionValue,
          answers
        })
      })

      const data = await response.json().catch(() => ({}))

      if (response.ok) {
        if (typeof data.lock_version === "number") {
          this.lockVersionValue = data.lock_version
        }
        this.setStatus(this.savedValue)
        if (data.status === "expired") {
          window.location.reload()
        }
      } else {
        this.setStatus(data.error || this.failedValue)
        if (data.status === "expired") {
          window.location.href = window.location.pathname.replace(/\/run$/, "/done")
        }
      }
    } catch (e) {
      this.setStatus(this.failedValue)
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}

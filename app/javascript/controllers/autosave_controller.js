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
    const answers = []

    for (const [key, value] of formData.entries()) {
      const match = key.match(/^answers\[(\d+)\]\[(.+)\]$/)
      if (!match) continue
      const questionId = match[1]
      const field = match[2]
      let entry = answers.find((a) => a.question_id === questionId)
      if (!entry) {
        entry = { question_id: questionId, payload: {} }
        answers.push(entry)
      }
      entry.payload[field] = value
    }
    return answers
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

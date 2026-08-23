import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    lightColor: { type: String, default: "#fbf7f1" },
    darkColor: { type: String, default: "#40362c" }
  }

  toggle() {
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    document.documentElement.style.colorScheme = next
    localStorage.setItem("theme", next)
    this.syncMeta(next)
  }

  syncMeta(theme) {
    const meta = document.querySelector('meta[name="theme-color"]')
    if (meta) meta.setAttribute("content", theme === "dark" ? this.darkColorValue : this.lightColorValue)
  }
}

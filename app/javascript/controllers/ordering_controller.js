import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "position"]

  connect() {
    this.selected = null
    this.dragging = false
    this.moved = false
    this.boundMove = this.dragMove.bind(this)
    this.boundEnd = this.dragEnd.bind(this)
    this.renumber()
  }

  disconnect() {
    this.unbindDrag()
  }

  place(event) {
    if (this.moved) {
      this.moved = false
      return
    }
    if (event.target.closest("[data-ordering-handle]")) return

    const item = event.currentTarget
    if (this.selected === item) {
      this.clearSelection()
      return
    }
    if (this.selected) {
      this.moveItem(this.selected, item)
      this.clearSelection()
      this.renumber()
      this.notifyChanged()
      return
    }

    this.selected = item
    this.applySelected(item, true)
  }

  keydown(event) {
    const item = event.currentTarget
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.place(event)
      return
    }
    if (event.key === "ArrowUp") {
      event.preventDefault()
      const prev = this.neighbor(item, -1)
      if (prev) {
        prev.before(item)
        item.focus()
        this.renumber()
        this.notifyChanged()
      }
    }
    if (event.key === "ArrowDown") {
      event.preventDefault()
      const next = this.neighbor(item, 1)
      if (next) {
        next.after(item)
        item.focus()
        this.renumber()
        this.notifyChanged()
      }
    }
    if (event.key === "Escape") this.clearSelection()
  }

  startDrag(event) {
    if (event.button != null && event.button !== 0) return

    event.preventDefault()
    event.stopPropagation()
    this.clearSelection()

    this.dragging = true
    this.moved = false
    this.dragItem = event.currentTarget.closest("[data-ordering-target='item']")
    this.dragItem.dataset.dragging = "true"
    event.currentTarget.setPointerCapture?.(event.pointerId)

    window.addEventListener("pointermove", this.boundMove)
    window.addEventListener("pointerup", this.boundEnd)
    window.addEventListener("pointercancel", this.boundEnd)
  }

  dragMove(event) {
    if (!this.dragging || !this.dragItem) return

    const others = this.itemTargets.filter((item) => item !== this.dragItem)
    const y = event.clientY
    let next = null
    for (const item of others) {
      const rect = item.getBoundingClientRect()
      if (y < rect.top + rect.height / 2) {
        next = item
        break
      }
    }

    if (next) {
      if (this.dragItem.nextElementSibling !== next) {
        next.before(this.dragItem)
        this.moved = true
      }
    } else {
      const last = others[others.length - 1]
      if (last && this.dragItem.previousElementSibling !== last) {
        last.after(this.dragItem)
        this.moved = true
      }
    }

    this.renumber()
  }

  dragEnd() {
    this.unbindDrag()
    this.dragItem?.removeAttribute("data-dragging")
    this.dragging = false
    this.dragItem = null
    this.renumber()
    if (this.moved) this.notifyChanged()
  }

  neighbor(item, offset) {
    const index = this.itemTargets.indexOf(item)
    return this.itemTargets[index + offset] || null
  }

  moveItem(fromEl, toEl) {
    if (fromEl === toEl) return
    const from = this.itemTargets.indexOf(fromEl)
    const to = this.itemTargets.indexOf(toEl)
    if (from < to) toEl.after(fromEl)
    else toEl.before(fromEl)
  }

  clearSelection() {
    if (this.selected) this.applySelected(this.selected, false)
    this.selected = null
  }

  applySelected(item, on) {
    item.setAttribute("aria-selected", on ? "true" : "false")
  }

  renumber() {
    this.positionTargets.forEach((badge, index) => {
      badge.textContent = String(index + 1)
    })
  }

  notifyChanged() {
    this.dispatch("changed")
  }

  unbindDrag() {
    window.removeEventListener("pointermove", this.boundMove)
    window.removeEventListener("pointerup", this.boundEnd)
    window.removeEventListener("pointercancel", this.boundEnd)
  }
}

import { Controller } from "@hotwired/stimulus"

// The answer is typed. Clipboard and dragged text are refused on this field
// alone: paste covers the shortcut and the context menu, dragover plus drop
// cover a dragged selection, and beforeinput covers browsers that insert
// clipboard text without firing paste.
export default class extends Controller {
  static targets = [ "notice" ]

  // dragover must be cancelled for a drop to be refusible, but it fires
  // continuously while the pointer is over the field, so it stays quiet.
  block(event) {
    event.preventDefault()
  }

  refuse(event) {
    this.block(event)
    this.reveal()
  }

  blockInsert(event) {
    if (event.inputType !== "insertFromPaste" && event.inputType !== "insertFromDrop" && event.inputType !== "insertFromYank") return

    event.preventDefault()
    this.reveal()
  }

  reveal() {
    if (!this.hasNoticeTarget) return

    this.noticeTarget.classList.remove("hidden")
  }
}

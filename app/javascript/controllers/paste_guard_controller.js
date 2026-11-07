import { Controller } from "@hotwired/stimulus"

// The answer is typed. Clipboard and dragged text are refused on this field
// alone: paste covers the shortcut and the context menu, dragover plus drop
// cover a dragged selection, and beforeinput covers browsers that insert
// clipboard text without firing paste.
export default class extends Controller {
  block(event) {
    event.preventDefault()
  }

  blockInsert(event) {
    if (event.inputType !== "insertFromPaste" && event.inputType !== "insertFromDrop" && event.inputType !== "insertFromYank") return

    event.preventDefault()
  }
}

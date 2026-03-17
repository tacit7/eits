// assets/js/hooks/note_full_editor.js
import {
  EditorView,
  keymap,
  highlightActiveLine,
  lineNumbers
} from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { oneDark } from "@codemirror/theme-one-dark"
import { markdown } from "@codemirror/lang-markdown"

export const NoteFullEditorHook = {
  mounted() {
    const body = this.el.dataset.body || ""
    const returnTo = this.el.dataset.returnTo || "/notes"
    const self = this

    const isDark = document.documentElement.dataset.theme === "dark"

    const statusEl = document.getElementById("note-editor-status")

    const saveKeymap = keymap.of([
      {
        key: "Mod-s",
        run(view) {
          self.pushEvent("note_saved", { body: view.state.doc.toString() })
          return true
        }
      },
      {
        key: "Escape",
        run() {
          window.location.href = returnTo
          return true
        }
      }
    ])

    const statusUpdate = EditorView.updateListener.of((update) => {
      if (!update.selectionSet && !update.docChanged) return
      if (!statusEl) return
      const pos = update.state.selection.main.head
      const line = update.state.doc.lineAt(pos)
      const col = pos - line.from + 1
      statusEl.textContent = `Ln ${line.number}, Col ${col}`
    })

    const extensions = [
      lineNumbers(),
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      saveKeymap,
      markdown(),
      EditorView.lineWrapping,
      statusUpdate,
    ]

    if (isDark) extensions.push(oneDark)

    const state = EditorState.create({ doc: body, extensions })
    this._view = new EditorView({ state, parent: this.el })

    // Wire save button click (button is outside hook el)
    const saveBtn = document.getElementById("note-save-btn")
    if (saveBtn) {
      this._saveBtnHandler = () => {
        self.pushEvent("note_saved", { body: self._view.state.doc.toString() })
      }
      saveBtn.addEventListener("click", this._saveBtnHandler)
    }

    this._view.focus()
  },

  destroyed() {
    const saveBtn = document.getElementById("note-save-btn")
    if (saveBtn && this._saveBtnHandler) {
      saveBtn.removeEventListener("click", this._saveBtnHandler)
    }
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}

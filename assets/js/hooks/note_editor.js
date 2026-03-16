// assets/js/hooks/note_editor.js
import { EditorView, keymap, highlightActiveLine } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { oneDark } from "@codemirror/theme-one-dark"
import { markdown } from "@codemirror/lang-markdown"

export const NoteEditorHook = {
  mounted() {
    const body = atob(this.el.dataset.body || "")
    const noteId = this.el.dataset.noteId
    this._saved = false
    const self = this

    const isDark = document.documentElement.dataset.theme === "dark"

    const saveKeymap = keymap.of([{
      key: "Mod-s",
      run(view) {
        self._saved = true
        self.pushEvent("note_saved", {
          note_id: noteId,
          body: view.state.doc.toString()
        })
        return true
      }
    }, {
      key: "Escape",
      run() {
        self.pushEvent("note_edit_cancelled", { note_id: noteId })
        return true
      }
    }])

    const extensions = [
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      saveKeymap,
      markdown(),
      EditorView.lineWrapping,
    ]

    if (isDark) extensions.push(oneDark)

    const state = EditorState.create({ doc: body, extensions })
    this._view = new EditorView({ state, parent: this.el })

    // Force the DaisyUI accordion open. LiveView does not re-set checked on
    // existing inputs after initial render, so we must do it imperatively.
    const collapseInput = this.el.closest(".collapse")?.querySelector("input[type=checkbox]")
    if (collapseInput) collapseInput.checked = true

    this._view.focus()
  },

  destroyed() {
    // pushEvent from destroyed() is best-effort — it may not reach the server
    // if the socket is already torn down. The LiveView recovers on the next
    // user interaction (clicking Edit again or page reload).
    if (!this._saved) {
      try { this.pushEvent("note_edit_cancelled", { note_id: this.el.dataset.noteId }) } catch (_) {}
    }
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}

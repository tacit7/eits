// assets/js/hooks/inline_note_creator.js
// CodeMirror-powered inline note creation editor.
// Pushes "save_new_note" with {title, body} to the LiveView.
import { EditorView, keymap, highlightActiveLine } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { oneDark } from "@codemirror/theme-one-dark"
import { markdown } from "@codemirror/lang-markdown"

export const InlineNoteCreatorHook = {
  mounted() {
    const self = this
    const isDark = document.documentElement.dataset.theme === "dark"

    const saveKeymap = keymap.of([
      {
        key: "Mod-s",
        run(view) {
          self._save(view)
          return true
        }
      },
      {
        key: "Escape",
        run() {
          self.pushEvent("close_new_note_editor", {})
          return true
        }
      }
    ])

    const extensions = [
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      saveKeymap,
      markdown(),
      EditorView.lineWrapping,
    ]

    if (isDark) extensions.push(oneDark)

    const state = EditorState.create({ doc: "", extensions })
    this._view = new EditorView({ state, parent: this.el })
    this._view.focus()

    const saveBtn = document.getElementById("inline-note-save-btn")
    if (saveBtn) {
      this._saveBtnHandler = () => self._save(self._view)
      saveBtn.addEventListener("click", this._saveBtnHandler)
    }
  },

  _save(view) {
    const titleEl = document.getElementById("new-note-title-input")
    const title = (titleEl?.value || "").trim()
    const body = view.state.doc.toString().trim()
    this.pushEvent("save_new_note", { title, body })
  },

  destroyed() {
    const saveBtn = document.getElementById("inline-note-save-btn")
    if (saveBtn && this._saveBtnHandler) {
      saveBtn.removeEventListener("click", this._saveBtnHandler)
    }
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}

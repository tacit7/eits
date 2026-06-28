// assets/js/hooks/note_full_editor.js
// CodeMirror is loaded lazily on first mount to keep the initial JS bundle small.

import { loadCMModulesAndCompartments, mountCMView, destroyCMView } from "./cm_editor_setup"

export const NoteFullEditorHook = {
  async mounted() {
    this._destroyed = false
    const body = this.el.dataset.body || ""
    const returnTo = this.el.dataset.returnTo || "/notes"
    const self = this

    const statusEl = document.getElementById("note-editor-status")

    const {
      EditorView, keymap, highlightActiveLine, lineNumbers,
      EditorState, defaultKeymap, history, historyKeymap,
      syntaxHighlighting, defaultHighlightStyle, markdown,
      themeExtension, tabExtension, fontExtension, vimExtension,
      watch, tabWatch, watchFont, watchVim,
    } = await loadCMModulesAndCompartments()

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

    const fillHeight = EditorView.theme({
      "&": { height: "100%" },
      ".cm-scroller": { overflow: "auto" }
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
      fillHeight,
      syntaxHighlighting(defaultHighlightStyle),
      themeExtension,
      tabExtension,
      fontExtension,
      vimExtension,
    ]

    if (this._destroyed) return
    mountCMView(this, { EditorState, EditorView, doc: body, extensions, watch, tabWatch, watchFont, watchVim })

    // Wire Tab on title input to focus the editor
    const titleInput = document.getElementById("note-title-input")
    if (titleInput) {
      this._titleTabHandler = (e) => {
        if (e.key === "Tab" && !e.shiftKey) {
          e.preventDefault()
          self._view.focus()
        }
      }
      titleInput.addEventListener("keydown", this._titleTabHandler)
    }

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
    this._destroyed = true
    const titleInput = document.getElementById("note-title-input")
    if (titleInput && this._titleTabHandler) {
      titleInput.removeEventListener("keydown", this._titleTabHandler)
    }
    const saveBtn = document.getElementById("note-save-btn")
    if (saveBtn && this._saveBtnHandler) {
      saveBtn.removeEventListener("click", this._saveBtnHandler)
    }
    destroyCMView(this)
  }
}

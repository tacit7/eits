// assets/js/hooks/note_full_editor.js
// CodeMirror is loaded lazily on first mount to keep the initial JS bundle small.

export const NoteFullEditorHook = {
  async mounted() {
    const body = this.el.dataset.body || ""
    const returnTo = this.el.dataset.returnTo || "/notes"
    const self = this

    const statusEl = document.getElementById("note-editor-status")

    const [
      { EditorView, keymap, highlightActiveLine, lineNumbers },
      { EditorState },
      { defaultKeymap, history, historyKeymap },
      { makeThemeCompartment },
      { markdown },
    ] = await Promise.all([
      import("@codemirror/view"),
      import("@codemirror/state"),
      import("@codemirror/commands"),
      import("../cm_theme"),
      import("@codemirror/lang-markdown"),
    ])

    const { extension: themeExtension, watch } = await makeThemeCompartment()

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
      themeExtension,
    ]

    const state = EditorState.create({ doc: body, extensions })
    this._view = new EditorView({ state, parent: this.el })
    this._cleanupTheme = watch(this._view)

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
    const titleInput = document.getElementById("note-title-input")
    if (titleInput && this._titleTabHandler) {
      titleInput.removeEventListener("keydown", this._titleTabHandler)
    }
    const saveBtn = document.getElementById("note-save-btn")
    if (saveBtn && this._saveBtnHandler) {
      saveBtn.removeEventListener("click", this._saveBtnHandler)
    }
    if (this._cleanupTheme) this._cleanupTheme()
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}

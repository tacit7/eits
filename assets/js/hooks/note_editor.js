// assets/js/hooks/note_editor.js
// CodeMirror is loaded lazily on first mount to keep the initial JS bundle small.

export const NoteEditorHook = {
  async mounted() {
    this._destroyed = false
    const body = atob(this.el.dataset.body || "")
    const noteId = this.el.dataset.noteId
    this._saved = false
    const self = this

    const [
      { EditorView, keymap, highlightActiveLine },
      { EditorState },
      { defaultKeymap, history, historyKeymap },
      { makeThemeCompartment },
      { makeTabSizeExtension, makeFontSizeExtension, makeVimExtension },
      { markdown },
    ] = await Promise.all([
      import("@codemirror/view"),
      import("@codemirror/state"),
      import("@codemirror/commands"),
      import("../cm_theme"),
      import("../cm_settings"),
      import("@codemirror/lang-markdown"),
    ])

    const { extension: themeExtension, watch } = await makeThemeCompartment()
    const { extension: tabExtension, watch: tabWatch } = await makeTabSizeExtension()
    const { extension: fontExtension, watch: watchFont } = await makeFontSizeExtension()
    const { extension: vimExtension, watch: watchVim } = await makeVimExtension()

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
      themeExtension,
      tabExtension,
      fontExtension,
      vimExtension,
    ]

    if (this._destroyed) return
    const state = EditorState.create({ doc: body, extensions })
    this._view = new EditorView({ state, parent: this.el })
    this._cleanupTheme = watch(this._view)
    this._cleanupTabSize = tabWatch(this._view)
    this._cleanupFontSize = watchFont(this._view)
    this._cleanupVim = watchVim(this._view)

    // Force the DaisyUI accordion open. LiveView does not re-set checked on
    // existing inputs after initial render, so we must do it imperatively.
    const collapseInput = this.el.closest(".collapse")?.querySelector("input[type=checkbox]")
    if (collapseInput) collapseInput.checked = true

    this._view.focus()
  },

  destroyed() {
    this._destroyed = true
    // pushEvent from destroyed() is best-effort — it may not reach the server
    // if the socket is already torn down. The LiveView recovers on the next
    // user interaction (clicking Edit again or page reload).
    if (!this._saved) {
      try { this.pushEvent("note_edit_cancelled", { note_id: this.el.dataset.noteId }) } catch (_) {}
    }
    if (this._cleanupTheme) this._cleanupTheme()
    if (this._cleanupTabSize) this._cleanupTabSize()
    if (this._cleanupFontSize) this._cleanupFontSize()
    if (this._cleanupVim) this._cleanupVim()
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}

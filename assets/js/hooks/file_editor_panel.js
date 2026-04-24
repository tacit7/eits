// File editor panel hook — multi-tab CodeMirror editor inside the Rail LiveComponent.
// Uses pushEventTo("#app-rail", ...) so save events go to the Rail LiveComponent,
// not the root LiveView (which is what plain pushEvent would do).

async function loadLanguage(lang) {
  switch (lang) {
    case "elixir": {
      const { elixir } = await import("codemirror-lang-elixir")
      return elixir()
    }
    case "javascript":
    case "typescript": {
      const { javascript } = await import("@codemirror/lang-javascript")
      return javascript({ typescript: lang === "typescript" })
    }
    case "css": {
      const { css } = await import("@codemirror/lang-css")
      return css()
    }
    case "html": {
      const { html } = await import("@codemirror/lang-html")
      return html()
    }
    case "markdown": {
      const { markdown } = await import("@codemirror/lang-markdown")
      return markdown()
    }
    case "json": {
      const { json } = await import("@codemirror/lang-json")
      return json()
    }
    default:
      return []
  }
}

export const FileEditorPanelHook = {
  async mounted() {
    this._setup()
  },

  async updated() {
    const newPath = this.el.dataset.path
    const newContent = atob(this.el.dataset.content || "")

    // Path changed — full reinit with new language
    if (newPath !== this._path) {
      this._teardown()
      this._setup()
      return
    }

    // Same file, content changed externally — patch in place
    if (this._view) {
      const current = this._view.state.doc.toString()
      if (newContent !== current) {
        this._view.dispatch({
          changes: { from: 0, to: current.length, insert: newContent },
        })
      }
      // Update tracked hash for conflict detection
      this._hash = this.el.dataset.hash || ""
    }
  },

  destroyed() {
    this._teardown()
  },

  async _setup() {
    this._teardown()
    this._gen = (this._gen || 0) + 1
    const gen = this._gen

    this._path = this.el.dataset.path || ""
    this._hash = this.el.dataset.hash || ""
    const content = atob(this.el.dataset.content || "")
    const lang = this.el.dataset.lang || "plaintext"
    const self = this

    try {
      const [
        { EditorView, keymap, lineNumbers, highlightActiveLine },
        { EditorState },
        { defaultKeymap, history, historyKeymap },
        { makeThemeCompartment },
        { makeTabSizeExtension, makeFontSizeExtension, makeVimExtension },
        { syntaxHighlighting, defaultHighlightStyle },
        langExtension,
      ] = await Promise.all([
        import("@codemirror/view"),
        import("@codemirror/state"),
        import("@codemirror/commands"),
        import("../cm_theme"),
        import("../cm_settings"),
        import("@codemirror/language"),
        loadLanguage(lang),
      ])

      if (gen !== this._gen) return

      const { extension: themeExtension, watch } = await makeThemeCompartment()
      const { extension: tabExtension, watch: tabWatch } = await makeTabSizeExtension()
      const { extension: fontExtension, watch: watchFont } = await makeFontSizeExtension()
      const { extension: vimExtension, watch: watchVim } = await makeVimExtension()

      if (gen !== this._gen) return

      const saveKeymap = keymap.of([{
        key: "Mod-s",
        run(view) {
          self.pushEventTo("#app-rail", "file_save", {
            path: self._path,
            content: view.state.doc.toString(),
            original_hash: self._hash,
          })
          return true
        },
      }])

      const heightTheme = EditorView.theme({
        "&": { height: "100%" },
        ".cm-scroller": { overflow: "auto" },
      })

      const state = EditorState.create({
        doc: content,
        extensions: [
          lineNumbers(),
          highlightActiveLine(),
          syntaxHighlighting(defaultHighlightStyle),
          themeExtension,
          tabExtension,
          fontExtension,
          langExtension,
          heightTheme,
          history(),
          keymap.of([...defaultKeymap, ...historyKeymap]),
          saveKeymap,
          vimExtension,
        ],
      })

      if (gen !== this._gen) return

      this._view = new EditorView({ state, parent: this.el })
      this._cleanupTheme = watch(this._view)
      this._cleanupTabSize = tabWatch(this._view)
      this._cleanupFontSize = watchFont(this._view)
      this._cleanupVim = watchVim(this._view)
    } catch (e) {
      console.error("[FileEditorPanel] mount error", e)
    }
  },

  _teardown() {
    this._gen = (this._gen || 0) + 1
    if (this._cleanupTheme) { this._cleanupTheme(); this._cleanupTheme = null }
    if (this._cleanupTabSize) { this._cleanupTabSize(); this._cleanupTabSize = null }
    if (this._cleanupFontSize) { this._cleanupFontSize(); this._cleanupFontSize = null }
    if (this._cleanupVim) { this._cleanupVim(); this._cleanupVim = null }
    if (this._view) { this._view.destroy(); this._view = null }
  },
}

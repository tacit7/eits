// assets/js/hooks/codemirror.js
// CodeMirror is loaded lazily on first mount to keep the initial JS bundle small.

async function loadLanguage(lang) {
  switch (lang) {
    case "elixir": {
      const { elixir } = await import("codemirror-lang-elixir")
      return elixir()
    }
    case "javascript": case "js": case "ts": {
      const { javascript } = await import("@codemirror/lang-javascript")
      return javascript()
    }
    case "css": {
      const { css } = await import("@codemirror/lang-css")
      return css()
    }
    case "html": case "heex": {
      const { html } = await import("@codemirror/lang-html")
      return html()
    }
    case "markdown": case "md": {
      const { markdown } = await import("@codemirror/lang-markdown")
      return markdown()
    }
    case "json": {
      const { json } = await import("@codemirror/lang-json")
      return json()
    }
    case "shell": case "sh": case "bash": {
      const [{ StreamLanguage }, { shell }] = await Promise.all([
        import("@codemirror/language"),
        import("@codemirror/legacy-modes/mode/shell"),
      ])
      return StreamLanguage.define(shell)
    }
    default: return []
  }
}

export const CodeMirrorHook = {
  async mounted() {
    this._teardown()
    this._gen = (this._gen || 0) + 1
    const gen = this._gen
    const content = atob(this.el.dataset.content || "")
    const lang = this.el.dataset.lang || "text"
    const readonly = this.el.dataset.readonly === "true"
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
        if (!readonly) self.pushEvent("file_changed", { content: view.state.doc.toString() })
        return true
      }
    }])

    const heightTheme = EditorView.theme({
      "&": { height: "100%" },
      ".cm-scroller": { overflow: "auto" },
    })

    const extensions = [
      lineNumbers(),
      highlightActiveLine(),
      syntaxHighlighting(defaultHighlightStyle),
      themeExtension,
      tabExtension,
      fontExtension,
      langExtension,
      heightTheme,
    ]

    if (readonly) {
      extensions.push(EditorState.readOnly.of(true))
    } else {
      extensions.push(history(), keymap.of([...defaultKeymap, ...historyKeymap]), saveKeymap, vimExtension)
    }

    const state = EditorState.create({ doc: content, extensions })

    if (gen !== this._gen) return
    this._view = new EditorView({ state, parent: this.el })
    this._cleanupTheme = watch(this._view)
    this._cleanupTabSize = tabWatch(this._view)
    this._cleanupFontSize = watchFont(this._view)
    this._cleanupVim = watchVim(this._view)
    } catch(e) { console.error("[CodeMirror] mount error", e) }
  },

  updated() {
    if (!this._view) {
      // imports were still in-flight when update arrived — let them finish
      return
    }
    const content = atob(this.el.dataset.content || "")
    const current = this._view.state.doc.toString()
    if (content !== current) {
      this._view.dispatch({
        changes: { from: 0, to: current.length, insert: content },
      })
    }
  },

  destroyed() {
    this._teardown()
  },

  _teardown() {
    // bump generation so any in-flight mount aborts
    this._gen = (this._gen || 0) + 1
    if (this._cleanupTheme) { this._cleanupTheme(); this._cleanupTheme = null }
    if (this._cleanupTabSize) { this._cleanupTabSize(); this._cleanupTabSize = null }
    if (this._cleanupFontSize) { this._cleanupFontSize(); this._cleanupFontSize = null }
    if (this._cleanupVim) { this._cleanupVim(); this._cleanupVim = null }
    if (this._view) { this._view.destroy(); this._view = null }
  },
}

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
    const content = atob(this.el.dataset.content || "")
    const lang = this.el.dataset.lang || "text"
    const self = this

    const [
      { EditorView, keymap, lineNumbers, highlightActiveLine },
      { EditorState },
      { defaultKeymap, history, historyKeymap },
      { oneDark },
      langExtension,
    ] = await Promise.all([
      import("@codemirror/view"),
      import("@codemirror/state"),
      import("@codemirror/commands"),
      import("@codemirror/theme-one-dark"),
      loadLanguage(lang),
    ])

    const saveKeymap = keymap.of([{
      key: "Mod-s",
      run(view) {
        self.pushEvent("file_changed", { content: view.state.doc.toString() })
        return true
      }
    }])

    const state = EditorState.create({
      doc: content,
      extensions: [
        lineNumbers(),
        highlightActiveLine(),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        saveKeymap,
        oneDark,
        langExtension,
      ]
    })

    this._view = new EditorView({ state, parent: this.el })
  },

  destroyed() {
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}

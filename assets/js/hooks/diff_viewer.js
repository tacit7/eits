// assets/js/hooks/diff_viewer.js
// Renders git diffs using codemirror-lang-diff for syntax-highlighted
// unified patch display with live theme switching.

import { makeThemeCompartment } from "../cm_theme"

export const DiffViewer = {
  async mounted() {
    this._view = null
    this._cleanup = null
    await this.render()
  },

  async updated() {
    this._teardown()
    await this.render()
  },

  async render() {
    const raw = this.el.dataset.diff
    if (!raw || raw === "__loading__" || raw === "__error__") return

    const [
      { EditorView },
      { EditorState },
      { diff },
      { syntaxHighlighting, defaultHighlightStyle },
    ] = await Promise.all([
      import("@codemirror/view"),
      import("@codemirror/state"),
      import("codemirror-lang-diff"),
      import("@codemirror/language"),
    ])

    const { extension: themeExtension, watch } = await makeThemeCompartment()

    this._view = new EditorView({
      state: EditorState.create({
        doc: raw,
        extensions: [
          EditorView.editable.of(false),
          EditorView.theme({ "&": { fontSize: "12px" } }),
          syntaxHighlighting(defaultHighlightStyle),
          themeExtension,
          diff(),
        ],
      }),
      parent: this.el,
    })

    this._cleanup = watch(this._view)
  },

  _teardown() {
    if (this._cleanup) this._cleanup()
    if (this._view) this._view.destroy()
    this._view = null
    this._cleanup = null
    if (this.el) this.el.innerHTML = ""
  },

  destroyed() {
    this._teardown()
  },
}

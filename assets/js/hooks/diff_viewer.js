// assets/js/hooks/diff_viewer.js
// Renders git diffs in a read-only CodeMirror editor with line-based
// decorations for GitHub-style +/- highlighting and live theme switching.
//
// codemirror-lang-diff provides no styleTags so we use a ViewPlugin that
// inspects each line's leading character to assign CSS classes.

import { makeThemeCompartment } from "../cm_theme"

// Line decoration classes applied based on first character(s) of each line.
let _decorationTypes = null
async function getDecorationTypes() {
  if (_decorationTypes) return _decorationTypes
  const { Decoration } = await import("@codemirror/view")
  _decorationTypes = {
    added:   Decoration.line({ class: "cm-diff-added" }),
    deleted: Decoration.line({ class: "cm-diff-deleted" }),
    hunk:    Decoration.line({ class: "cm-diff-hunk" }),
    meta:    Decoration.line({ class: "cm-diff-meta" }),
  }
  return _decorationTypes
}

async function makeDiffHighlight() {
  const [{ ViewPlugin, Decoration }, { RangeSetBuilder }] = await Promise.all([
    import("@codemirror/view"),
    import("@codemirror/state"),
  ])
  const types = await getDecorationTypes()

  function buildDecorations(view) {
    const builder = new RangeSetBuilder()
    for (const { from, to } of view.visibleRanges) {
      let pos = from
      while (pos <= to) {
        const line = view.state.doc.lineAt(pos)
        const t = line.text
        if (t.startsWith("+") && !t.startsWith("+++")) {
          builder.add(line.from, line.from, types.added)
        } else if (t.startsWith("-") && !t.startsWith("---")) {
          builder.add(line.from, line.from, types.deleted)
        } else if (t.startsWith("@@")) {
          builder.add(line.from, line.from, types.hunk)
        } else if (
          t.startsWith("diff ") || t.startsWith("index ") ||
          t.startsWith("---")   || t.startsWith("+++") ||
          t.startsWith("new file") || t.startsWith("deleted file") ||
          t.startsWith("rename") || t.startsWith("similarity") ||
          t.startsWith("Binary")
        ) {
          builder.add(line.from, line.from, types.meta)
        }
        pos = line.to + 1
      }
    }
    return builder.finish()
  }

  return ViewPlugin.fromClass(
    class {
      constructor(view) { this.decorations = buildDecorations(view) }
      update(u) {
        if (u.docChanged || u.viewportChanged) this.decorations = buildDecorations(u.view)
      }
    },
    { decorations: v => v.decorations }
  )
}

export const DiffViewer = {
  async mounted() {
    this._destroyed = false
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
      diffHighlight,
      { extension: themeExtension, watch },
    ] = await Promise.all([
      import("@codemirror/view"),
      import("@codemirror/state"),
      makeDiffHighlight(),
      makeThemeCompartment(),
    ])

    // Guard: destroyed() may have fired while awaiting the dynamic imports.
    if (this._destroyed) return

    this._view = new EditorView({
      state: EditorState.create({
        doc: raw,
        extensions: [
          EditorView.editable.of(false),
          EditorView.theme({ "&": { fontSize: "12px" } }),
          themeExtension,
          diffHighlight,
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
    this._destroyed = true
    this._teardown()
  },
}

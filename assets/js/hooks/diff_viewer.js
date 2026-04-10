// assets/js/hooks/diff_viewer.js
// Renders git diffs using @codemirror/merge (unifiedMergeView) with
// syntax highlighting and live theme switching. Replaces diff2html.

import { makeThemeCompartment } from "../cm_theme"

// Parse a `git show --unified=N` patch into per-file {name, original, modified}.
// We only have the changed hunks + context lines — not the full file — but that's
// enough to render a meaningful diff.
function parsePatch(raw) {
  const files = []
  let name = null
  let originalLines = []
  let modifiedLines = []
  let inHunk = false

  for (const line of raw.split("\n")) {
    if (line.startsWith("diff --git ")) {
      if (name !== null) {
        files.push({ name, original: originalLines.join("\n"), modified: modifiedLines.join("\n") })
      }
      const m = line.match(/diff --git a\/(.*) b\/(.*)/)
      name = m ? m[2] : "unknown"
      originalLines = []
      modifiedLines = []
      inHunk = false
    } else if (line.startsWith("@@ ")) {
      // Hunk separator — add a blank line between hunks for readability
      if (inHunk) {
        originalLines.push("")
        modifiedLines.push("")
      }
      inHunk = true
    } else if (!inHunk) {
      // Commit metadata before first hunk — skip
    } else if (line.startsWith("--- ") || line.startsWith("+++ ")) {
      // File headers inside hunks — skip
    } else if (line.startsWith("-")) {
      originalLines.push(line.slice(1))
    } else if (line.startsWith("+")) {
      modifiedLines.push(line.slice(1))
    } else if (line.startsWith(" ")) {
      // Context line — present in both versions
      originalLines.push(line.slice(1))
      modifiedLines.push(line.slice(1))
    }
    // else: "\ No newline at end of file" etc — skip
  }

  if (name !== null) {
    files.push({ name, original: originalLines.join("\n"), modified: modifiedLines.join("\n") })
  }

  return files.filter(f => f.original !== "" || f.modified !== "")
}

async function loadLangForFile(filename) {
  const ext = filename.split(".").pop().toLowerCase()
  switch (ext) {
    case "ex":
    case "exs":
    case "heex": {
      const { elixir } = await import("codemirror-lang-elixir")
      return elixir()
    }
    case "js":
    case "ts":
    case "jsx":
    case "tsx": {
      const { javascript } = await import("@codemirror/lang-javascript")
      return javascript()
    }
    case "json": {
      const { json } = await import("@codemirror/lang-json")
      return json()
    }
    case "css": {
      const { css } = await import("@codemirror/lang-css")
      return css()
    }
    case "html": {
      const { html } = await import("@codemirror/lang-html")
      return html()
    }
    case "md": {
      const { markdown } = await import("@codemirror/lang-markdown")
      return markdown()
    }
    case "sh":
    case "bash": {
      const [{ StreamLanguage }, { shell }] = await Promise.all([
        import("@codemirror/language"),
        import("@codemirror/legacy-modes/mode/shell"),
      ])
      return StreamLanguage.define(shell)
    }
    default:
      return []
  }
}

export const DiffViewer = {
  async mounted() {
    this._views = []
    this._cleanups = []
    await this.render()
  },

  async updated() {
    this._teardown()
    await this.render()
  },

  async render() {
    const raw = this.el.dataset.diff
    if (!raw || raw === "__loading__" || raw === "__error__") return

    const files = parsePatch(raw)
    if (files.length === 0) return

    const [
      { EditorView },
      { EditorState },
      { unifiedMergeView },
      { syntaxHighlighting, defaultHighlightStyle },
    ] = await Promise.all([
      import("@codemirror/view"),
      import("@codemirror/state"),
      import("@codemirror/merge"),
      import("@codemirror/language"),
    ])

    this.el.innerHTML = ""

    for (const file of files) {
      const wrapper = document.createElement("div")
      wrapper.className = "cm-diff-file"

      const header = document.createElement("div")
      header.className = "cm-diff-filename"
      header.textContent = file.name
      wrapper.appendChild(header)

      const editorEl = document.createElement("div")
      wrapper.appendChild(editorEl)
      this.el.appendChild(wrapper)

      const [{ extension: themeExtension, watch }, langExtension] = await Promise.all([
        makeThemeCompartment(),
        loadLangForFile(file.name),
      ])

      const view = new EditorView({
        state: EditorState.create({
          doc: file.modified,
          extensions: [
            EditorView.editable.of(false),
            EditorView.theme({ "&": { fontSize: "12px" } }),
            syntaxHighlighting(defaultHighlightStyle),
            themeExtension,
            langExtension,
            unifiedMergeView({
              original: file.original,
              highlightChanges: true,
              gutter: false,
              syntaxHighlightDeletions: true,
            }),
          ],
        }),
        parent: editorEl,
      })

      this._views.push(view)
      this._cleanups.push(watch(view))
    }
  },

  _teardown() {
    this._cleanups.forEach(fn => fn?.())
    this._views.forEach(v => v.destroy())
    this._views = []
    this._cleanups = []
    if (this.el) this.el.innerHTML = ""
  },

  destroyed() {
    this._teardown()
  },
}

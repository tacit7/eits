// assets/js/cm_settings.js
// Shared CodeMirror settings extensions (tab size, font size).
// Loaded lazily — only imported by editor hooks, not at app startup.

export async function makeTabSizeExtension() {
  const [{ EditorState, Compartment }, { indentUnit }] = await Promise.all([
    import("@codemirror/state"),
    import("@codemirror/language"),
  ])

  const compartment = new Compartment()
  const tabSize = parseInt(document.documentElement.dataset.cmTabSize || "2", 10)
  const spaces = " ".repeat(tabSize)

  return {
    extension: compartment.of([indentUnit.of(spaces), EditorState.tabSize.of(tabSize)]),
    watch(view) {
      const handler = ({ detail }) => {
        const size = parseInt(detail.cm_tab_size || "2", 10)
        const sp = " ".repeat(size)
        view.dispatch({
          effects: compartment.reconfigure([indentUnit.of(sp), EditorState.tabSize.of(size)])
        })
      }
      window.addEventListener("phx:apply_cm_settings", handler)
      return () => window.removeEventListener("phx:apply_cm_settings", handler)
    }
  }
}

// Returns an extension seeded with the current font size, plus a watch()
// function to wire live switching once the EditorView is created.
export async function makeFontSizeExtension() {
  const { EditorView } = await import("@codemirror/view")
  const { Compartment } = await import("@codemirror/state")
  const compartment = new Compartment()
  const size = document.documentElement.dataset.cmFontSize || "14"
  const makeTheme = (sz) =>
    EditorView.theme({
      "&": { fontSize: sz + "px" },
      ".cm-scroller": { fontFamily: "monospace" },
    })

  return {
    extension: compartment.of(makeTheme(size)),
    watch(view) {
      const handler = ({ detail }) => {
        if (detail.cm_font_size) {
          view.dispatch({ effects: compartment.reconfigure(makeTheme(detail.cm_font_size)) })
        }
      }
      window.addEventListener("phx:apply_cm_settings", handler)
      return () => window.removeEventListener("phx:apply_cm_settings", handler)
    },
  }
}

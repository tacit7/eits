// assets/js/cm_settings.js
// Shared CodeMirror settings extensions (font size, etc.)
// Loaded lazily — only imported by editor hooks, not at app startup.

// Returns an extension seeded with the current font size, plus a watch()
// function to wire live switching once the EditorView is created.
//
//   const { extension: fontExtension, watch } = await makeFontSizeExtension()
//   // ... create EditorView with fontExtension in extensions ...
//   this._cleanupFontSize = watch(this._view)
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

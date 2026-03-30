// Lazy-loaded CodeMirror tab size management. Loaded on first editor mount,
// not at app startup, to keep the initial bundle small.
//
// Reads from document.documentElement.dataset.cmTabSize (set in root.html.heex)
// and listens for phx:apply_cm_settings to update live editors.

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

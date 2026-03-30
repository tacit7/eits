// assets/js/cm_settings.js
// Lazy-loaded CodeMirror settings extensions (vim mode, etc.)

const isVim = () => document.documentElement.dataset.cmVim === "true"

// Returns an extension seeded with the current vim state, plus a watch()
// function to wire live toggling once the EditorView is created.
//
//   const { extension: vimExtension, watch } = await makeVimExtension()
//   // ... create EditorView with vimExtension in extensions ...
//   this._cleanupVim = watch(this._view)
export async function makeVimExtension() {
  const { Compartment } = await import("@codemirror/state")
  const compartment = new Compartment()

  const loadVim = async () => {
    if (!isVim()) return []
    const { vim } = await import("@replit/codemirror-vim")
    return vim()
  }

  return {
    extension: compartment.of(await loadVim()),
    watch(view) {
      const handler = async ({ detail }) => {
        if (detail.cm_vim === undefined) return
        let ext = []
        if (detail.cm_vim === "true") {
          const { vim } = await import("@replit/codemirror-vim")
          ext = vim()
        }
        view.dispatch({ effects: compartment.reconfigure(ext) })
      }
      window.addEventListener("phx:apply_cm_settings", handler)
      return () => window.removeEventListener("phx:apply_cm_settings", handler)
    },
  }
}

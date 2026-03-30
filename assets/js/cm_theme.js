// assets/js/cm_theme.js
// Lazy-loaded CodeMirror theme management. Loaded on first editor mount,
// not at app startup, to keep the initial bundle small.
//
// dark       → bespin
// light      → eclipse
// dracula    → dracula
// tokyonight → tokyoNight

const THEME_KEY = {
  dark: "bespin",
  light: "eclipse",
  dracula: "dracula",
  tokyonight: "tokyoNight",
}

let _modules = null

async function ensureModules() {
  if (_modules) return _modules
  const [
    { Compartment },
    { bespin },
    { eclipse },
    { dracula },
    { tokyoNight },
  ] = await Promise.all([
    import("@codemirror/state"),
    import("@uiw/codemirror-theme-bespin"),
    import("@uiw/codemirror-theme-eclipse"),
    import("@uiw/codemirror-theme-dracula"),
    import("@uiw/codemirror-theme-tokyo-night"),
  ])
  _modules = { Compartment, bespin, eclipse, dracula, tokyoNight }
  return _modules
}

function resolveTheme(modules, appTheme) {
  const key = THEME_KEY[appTheme] ?? "bespin"
  return modules[key]
}

// Returns an extension seeded with the current app theme, plus a watch()
// function to wire live switching once the EditorView is created.
//
//   const { extension: themeExtension, watch } = await makeThemeCompartment()
//   // ... create EditorView with themeExtension in extensions ...
//   this._cleanupTheme = watch(this._view)
export async function makeThemeCompartment() {
  const modules = await ensureModules()
  const { Compartment } = modules
  const compartment = new Compartment()
  const appTheme = document.documentElement.dataset.theme || "dark"

  return {
    extension: compartment.of(resolveTheme(modules, appTheme)),
    watch(view) {
      const handler = ({ detail }) => {
        view.dispatch({
          effects: compartment.reconfigure(resolveTheme(modules, detail.theme))
        })
      }
      window.addEventListener("phx:apply_theme", handler)
      return () => window.removeEventListener("phx:apply_theme", handler)
    },
  }
}

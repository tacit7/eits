// assets/js/cm_lang.js
// Shared CodeMirror language loader used by both the CodeMirrorHook and FileEditor.svelte.
// Returns a LanguageSupport extension for the given lang string, or null for unknown langs.
// Callers must handle null (filter from extensions array or pass as-is to svelte-codemirror-editor).

export async function loadLanguage(lang) {
  switch (lang) {
    case "elixir": {
      const { elixir } = await import("codemirror-lang-elixir")
      return elixir()
    }
    case "javascript":
    case "js": {
      const { javascript } = await import("@codemirror/lang-javascript")
      return javascript()
    }
    case "typescript":
    case "ts": {
      const { javascript } = await import("@codemirror/lang-javascript")
      return javascript({ typescript: true })
    }
    case "css": {
      const { css } = await import("@codemirror/lang-css")
      return css()
    }
    case "html":
    case "heex": {
      const { html } = await import("@codemirror/lang-html")
      return html()
    }
    case "markdown":
    case "md": {
      const { markdown } = await import("@codemirror/lang-markdown")
      return markdown()
    }
    case "json": {
      const { json } = await import("@codemirror/lang-json")
      return json()
    }
    case "shell":
    case "sh":
    case "bash": {
      const [{ StreamLanguage }, { shell }] = await Promise.all([
        import("@codemirror/language"),
        import("@codemirror/legacy-modes/mode/shell"),
      ])
      return StreamLanguage.define(shell)
    }
    default:
      return null
  }
}

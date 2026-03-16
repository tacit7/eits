// assets/js/hooks/codemirror.js
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { oneDark } from "@codemirror/theme-one-dark"
import { javascript } from "@codemirror/lang-javascript"
import { css } from "@codemirror/lang-css"
import { html } from "@codemirror/lang-html"
import { markdown } from "@codemirror/lang-markdown"
import { StreamLanguage } from "@codemirror/language"
import { shell } from "@codemirror/legacy-modes/mode/shell"
import { elixir } from "codemirror-lang-elixir"

function getLanguageExtension(lang) {
  switch (lang) {
    case "elixir": return elixir()
    case "javascript": case "js": case "ts": return javascript()
    case "css": return css()
    case "html": case "heex": return html()
    case "markdown": case "md": return markdown()
    case "shell": case "sh": case "bash": return StreamLanguage.define(shell)
    default: return []
  }
}

export const CodeMirrorHook = {
  mounted() {
    const content = atob(this.el.dataset.content || "")
    const lang = this.el.dataset.lang || "text"
    const self = this

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
        getLanguageExtension(lang),
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

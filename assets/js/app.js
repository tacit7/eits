// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {CopyToClipboard} from "./hooks/copy_to_clipboard"
import {CopySessionId} from "./hooks/copy_session_id"
import {BookmarkAgent} from "./hooks/bookmark_agent"
import {ScrollToBottom} from "./hooks/scroll_to_bottom"
import {MarkdownMessage} from "./hooks/markdown_message"
import {CommandHistory} from "./hooks/command_history"
import {getHooks} from "live_svelte"
import "./theme"
import hljs from 'highlight.js'
// highlight.js theme is handled in app.css (theme-aware)

// Import Svelte components manually (esbuild doesn't support import.meta.glob)
import SessionsSidebar from "../svelte/components/SessionsSidebar.svelte"
import MainWorkArea from "../svelte/components/MainWorkArea.svelte"
import ContextPanel from "../svelte/components/ContextPanel.svelte"
import TasksTab from "../svelte/components/tabs/TasksTab.svelte"
import CommitsTab from "../svelte/components/tabs/CommitsTab.svelte"
import LogsTab from "../svelte/components/tabs/LogsTab.svelte"
import NotesTab from "../svelte/components/tabs/NotesTab.svelte"
import AgentDetail from "../svelte/components/AgentDetail.svelte"
import AgentMessagesPanel from "../svelte/components/tabs/AgentMessagesPanel.svelte"
import FABFlower from "../svelte/components/FABFlower.svelte"

let Hooks = getHooks({
  SessionsSidebar,
  MainWorkArea,
  ContextPanel,
  TasksTab,
  CommitsTab,
  LogsTab,
  NotesTab,
  AgentDetail,
  AgentMessagesPanel,
  FABFlower
})
Hooks.CopyToClipboard = CopyToClipboard
Hooks.CopySessionId = CopySessionId
Hooks.BookmarkAgent = BookmarkAgent
Hooks.ScrollToBottom = ScrollToBottom
Hooks.CommandHistory = CommandHistory
Hooks.MarkdownMessage = MarkdownMessage
Hooks.RefreshDot = {
  mounted() { this._flash() },
  updated() { this._flash() },
  _flash() {
    this.el.style.opacity = "1"
    clearTimeout(this._timer)
    this._timer = setTimeout(() => { this.el.style.opacity = "0" }, 600)
  }
}
Hooks.Highlight = {
  mounted() {
    hljs.highlightElement(this.el)
  },
  updated() {
    hljs.highlightElement(this.el)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 5000,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


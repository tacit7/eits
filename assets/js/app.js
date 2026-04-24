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
import {FloatingChat} from "./hooks/floating_chat"
import {ScrollToBottom} from "./hooks/scroll_to_bottom"
import {AutoScroll} from "./hooks/auto_scroll"
import {MarkdownMessage} from "./hooks/markdown_message"
// CommandHistory composes SlashCommandPopup internally (see hooks/command_history.js).
// Phoenix allows only one phx-hook per element, so SlashCommandPopup is NOT registered
// here — it is imported and called via SlashCommandPopup.mounted.call(this) inside
// CommandHistory.mounted() to share the same hook context.
import {CommandHistory} from "./hooks/command_history"
import {DiffViewer} from "./hooks/diff_viewer"
import {DiffCollapse} from "./hooks/diff_collapse"
import {PasskeyAuth} from "./hooks/passkey_auth"
import {InfiniteScroll} from "./hooks/infinite_scroll"
import {DmComposer} from "./hooks/dm_composer"
import {FileAttach} from "./hooks/file_attach"
import {PushSetup} from "./push_notifications"
import {SwipeRow} from "./hooks/swipe_row"
import {ConfigChatGuide} from "./hooks/config_chat_guide"
import {CodeMirrorHook} from "./hooks/codemirror"
const FileEditorRelay = {
  mounted() {
    this._handler = (e) => {
      this.pushEventTo("#app-rail", "file_save", e.detail)
    }
    window.addEventListener("file:save", this._handler)
  },
  destroyed() {
    window.removeEventListener("file:save", this._handler)
  },
}
import {NoteEditorHook} from "./hooks/note_editor"
import {NoteFullEditorHook} from "./hooks/note_full_editor"
import {SortableKanban, SortableColumns} from "./hooks/sortable_kanban"
import {KanbanKeyboard, KanbanScrollDots} from "./hooks/kanban_keyboard"
import {ModalDialog} from "./hooks/modal_dialog"
import {LiveStreamToggle} from "./hooks/live_stream_toggle"
import {RefreshDot} from "./hooks/refresh_dot"
import {Highlight} from "./hooks/highlight"
import {LocalTime} from "./hooks/local_time"
import {DragUpload} from "./hooks/drag_upload"
import {SidebarState} from "./hooks/sidebar_state"
import {RailState} from "./hooks/rail_state"
import {DrawerSwipeClose} from "./hooks/drawer_swipe_close"
import {QuickCreateNote, QuickCreateAgent, QuickUpdateAgent, QuickGetAgent, QuickDeleteAgent, QuickResumeAgent, QuickCreateChat, QuickCreateTask} from "./hooks/quick_create"
import {CommandPalette} from "./hooks/command_palette"
import {FlashTimeout} from "./hooks/flash_timeout"
import {ReloadConfirmModal} from "./hooks/reload_confirm_modal"
import {ChatWindowHook} from "./hooks/chat_window_hook"
import {CanvasLayoutHook} from "./hooks/canvas_layout_hook"
import {CanvasTabHook, CanvasStatusHook} from "./hooks/canvas_tab_hook"
import {CanvasPanHook} from "./hooks/canvas_pan_hook"
import {TimerCountdown} from "./hooks/timer_countdown"
import {SessionsDropdownGuard} from "./hooks/sessions_dropdown_guard"
import {AgentCombobox} from "./hooks/agent_combobox"
import {GlobalKeydown} from "./hooks/global_keydown"
import {showToast} from "./hooks/utils"
import {getHooks} from "live_svelte"
import "./theme"

// Auto-discover Svelte components via live_svelte's Vite plugin.
// The virtual module keys include the path (e.g. "components/tabs/TasksTab"),
// but Elixir templates reference bare names (e.g. name="TasksTab"), so we
// strip the directory prefix to produce a flat name -> Component map.
import _components from "virtual:live-svelte-components"

const components = Object.fromEntries(
  Object.entries(_components).map(([key, comp]) => [key.split("/").pop(), comp])
)

let Hooks = getHooks(components)
Hooks.CopyToClipboard = CopyToClipboard
Hooks.CopySessionId = CopySessionId
Hooks.BookmarkAgent = BookmarkAgent
Hooks.FloatingChat = FloatingChat
Hooks.ScrollToBottom = ScrollToBottom
Hooks.AutoScroll = AutoScroll
Hooks.CommandHistory = CommandHistory
Hooks.MarkdownMessage = MarkdownMessage
Hooks.DiffViewer = DiffViewer
Hooks.DiffCollapse = DiffCollapse
Hooks.PasskeyAuth = PasskeyAuth
Hooks.PushSetup = PushSetup
Hooks.InfiniteScroll = InfiniteScroll
Hooks.DmComposer = DmComposer
Hooks.FileAttach = FileAttach
Hooks.SwipeRow = SwipeRow
Hooks.ConfigChatGuide = ConfigChatGuide
Hooks.CodeMirror = CodeMirrorHook
Hooks.FileEditorRelay = FileEditorRelay
Hooks.NoteEditor = NoteEditorHook
Hooks.NoteFullEditor = NoteFullEditorHook
Hooks.SortableKanban = SortableKanban
Hooks.SortableColumns = SortableColumns
Hooks.KanbanKeyboard = KanbanKeyboard
Hooks.KanbanScrollDots = KanbanScrollDots
Hooks.ModalDialog = ModalDialog
Hooks.LiveStreamToggle = LiveStreamToggle
Hooks.RefreshDot = RefreshDot
Hooks.Highlight = Highlight
Hooks.LocalTime = LocalTime
Hooks.DragUpload = DragUpload
Hooks.SidebarState = SidebarState
Hooks.RailState = RailState
Hooks.DrawerSwipeClose = DrawerSwipeClose
Hooks.QuickCreateNote = QuickCreateNote
Hooks.QuickCreateAgent = QuickCreateAgent
Hooks.QuickUpdateAgent = QuickUpdateAgent
Hooks.QuickGetAgent = QuickGetAgent
Hooks.QuickDeleteAgent = QuickDeleteAgent
Hooks.QuickResumeAgent = QuickResumeAgent
Hooks.QuickCreateChat = QuickCreateChat
Hooks.QuickCreateTask = QuickCreateTask
Hooks.CommandPalette = CommandPalette
Hooks.FlashTimeout = FlashTimeout
Hooks.ReloadConfirmModal = ReloadConfirmModal
Hooks.ChatWindowHook = ChatWindowHook
Hooks.CanvasLayoutHook = CanvasLayoutHook
Hooks.CanvasTabHook = CanvasTabHook
Hooks.CanvasStatusHook = CanvasStatusHook
Hooks.CanvasPanHook = CanvasPanHook
Hooks.TimerCountdown = TimerCountdown
Hooks.SessionsDropdownGuard = SessionsDropdownGuard
Hooks.AgentCombobox = AgentCombobox
Hooks.GlobalKeydown = GlobalKeydown

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:file-editor-open", () => {
  document.getElementById("app-rail")?.classList.add("flex-1")
  document.getElementById("main-content-wrapper")?.classList.add("hidden")
})

window.addEventListener("phx:file-editor-close", () => {
  document.getElementById("app-rail")?.classList.remove("flex-1")
  document.getElementById("main-content-wrapper")?.classList.remove("hidden")
})

window.addEventListener("phx:copy_to_clipboard", (e) => {
  const { text, format, error } = e.detail

  if (error) {
    showToast("Failed to copy")
    return
  }

  if (!text || !navigator.clipboard) return

  navigator.clipboard.writeText(text).then(() => {
    showToast(`Copied as ${format}`)
  }).catch(err => {
    console.error("Failed to copy:", err)
    showToast("Failed to copy")
  })
})

// Copy button handler for tool call / tool result blocks (data-copy-btn attribute).
// Uses capture phase so we can stop propagation before <summary> toggles the <details>.
document.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-copy-btn]")
  if (!btn) return
  e.stopPropagation()
  e.preventDefault()
  const text = btn.dataset.copyText ?? ""
  navigator.clipboard?.writeText(text).then(() => {
    btn.dataset.copied = "1"
    setTimeout(() => delete btn.dataset.copied, 2000)
  })
}, true)

// Persist sidebar collapse state on toggle
window.addEventListener("click", (e) => {
  const btn = e.target.closest("[phx-click='toggle_collapsed']")
  if (btn) {
    const sidebar = document.getElementById("app-rail")
    if (sidebar) {
      // Toggle: if currently expanded on desktop, it's about to collapse
      const isCurrentlyExpanded = sidebar.classList.contains("md:w-60")
      localStorage.setItem("sidebar_collapsed", isCurrentlyExpanded ? "true" : "false")
    }
  }
})

// connect if there are any LiveViews on the page.
// Guard against double-execution: Vite exports a __vite_preload helper from this entry
// chunk, so any dynamic import (codemirror, highlight.js, etc.) triggers the browser to
// load this module a second time under a different URL (without the ?vsn=d cache-buster).
// Since ES modules are keyed by URL, these are treated as distinct module instances.
// The guard ensures the second evaluation is a no-op — the first LiveSocket wins.
if (!window.liveSocket) {
  liveSocket.connect()
  window.liveSocket = liveSocket
}

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (import.meta.env.DEV) {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Server log streaming to the browser console is disabled — too noisy.
    // To re-enable temporarily, call reloader.enableServerLogs() from DevTools.

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

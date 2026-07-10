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
import {EditorLayout, installEditorWindowListeners} from "./hooks/editor_layout"
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
import {PtyHook} from "./hooks/pty_hook"
import {TerminalHook} from "./hooks/terminal_hook"
import {TerminalWindowHook} from "./hooks/terminal_window_hook"
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
import {RailState} from "./hooks/rail_state"
import {CtxMenu} from "./hooks/context_menu"
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
import {IndeterminateCheckbox} from "./hooks/indeterminate_checkbox"
import {ShiftSelect} from "./hooks/shift_select"
import {AgentCombobox} from "./hooks/agent_combobox"
import {ModelSelectorPopup} from "./hooks/model_selector_popup"
import {GlobalKeydown} from "./hooks/global_keydown"
import {DmHistoryCleanup} from "./hooks/dm_history_cleanup"
import {PreserveDetails} from "./hooks/preserve_details"
import {ExpandOnSearch} from "./hooks/expand_on_search"
import {SearchHighlight} from "./hooks/search_highlight"
import {VimNav} from "./hooks/vim_nav"
import {TaskListSelection} from "./hooks/task_list_selection"
import {DrawerDirtyForm} from "./hooks/drawer_dirty_form"
import {showToast, showSessionFailureToast} from "./hooks/utils"
import SortDropdown from "./hooks/sort_dropdown"
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
Hooks.EditorLayout = EditorLayout
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
Hooks.RailState = RailState
Hooks.CtxMenu = CtxMenu
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
Hooks.IndeterminateCheckbox = IndeterminateCheckbox
Hooks.ShiftSelect = ShiftSelect
Hooks.AgentCombobox = AgentCombobox
Hooks.ModelSelectorPopup = ModelSelectorPopup
Hooks.GlobalKeydown = GlobalKeydown
Hooks.DmHistoryCleanup = DmHistoryCleanup
Hooks.PreserveDetails = PreserveDetails
Hooks.ExpandOnSearch = ExpandOnSearch
Hooks.SearchHighlight = SearchHighlight
Hooks.SortDropdown = SortDropdown
Hooks.TaskListSelection = TaskListSelection
Hooks.DrawerDirtyForm = DrawerDirtyForm
Hooks.PtyHook = PtyHook
Hooks.TerminalHook = TerminalHook
Hooks.TerminalWindowHook = TerminalWindowHook
// VimNav is initialized directly below (not via phx-hook)

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
// Track navigation kind so we can reset main scroll on full navigations only.
// phx:page-loading-stop doesn't carry detail; capture kind from start and apply on stop.
let _pendingNavKind = null
window.addEventListener("phx:page-loading-start", (e) => {
  _pendingNavKind = e.detail?.kind ?? null
  topbar.show(300)
})
window.addEventListener("phx:page-loading-stop", (_info) => {
  topbar.hide()
  // Reset main scroll on navigate (not patch/submit) so pages always start at the top.
  // Without this, scrolling down the sessions list then clicking a session leaves
  // #main-content scrolled, hiding the DM composer below the viewport.
  if (_pendingNavKind === "navigate") {
    const main = document.getElementById("main-content")
    if (main) main.scrollTop = 0
  }
  _pendingNavKind = null
})

// Editor layout: source of truth on <html data-editor-mode>, owned by the
// EditorLayout hook on #file-editor-pane. Window-level listeners handle
// open/close + reconnect — see hooks/editor_layout.js for details.
installEditorWindowListeners()

window.addEventListener("phx:session:failed", (e) => {
  showSessionFailureToast(e.detail || {})
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

// Copy button handler for tool call / tool result blocks and message bubbles
// (data-copy-btn attribute). Uses capture phase so we can stop propagation
// before <summary> toggles the <details>. Swaps the button's icon to a
// checkmark for a couple seconds so the click has visible feedback.
const COPY_BTN_CHECK_ICON =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-3.5" aria-hidden="true">' +
  '<path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd"/></svg>'

document.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-copy-btn]")
  if (!btn || btn.dataset.copied) return
  e.stopPropagation()
  e.preventDefault()
  const text = btn.dataset.copyText ?? ""
  navigator.clipboard?.writeText(text).then(() => {
    btn.dataset.copied = "1"
    const originalHtml = btn.innerHTML
    btn.innerHTML = COPY_BTN_CHECK_ICON
    setTimeout(() => {
      btn.innerHTML = originalHtml
      delete btn.dataset.copied
    }, 1500)
  })
}, true)

// Rail divider double-click = collapse/expand (bonus gesture; the hover
// chevron #rail-collapse-toggle is the discoverable affordance). Persistence
// happens server-side via the RailState hook's save_rail_state patch.
window.addEventListener("dblclick", (e) => {
  if (e.target.closest("#rail-divider")) {
    document.getElementById("rail-collapse-toggle")?.click()
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

// --- vsbar: socket status dot + server port ---------------------------------
// data-socket on <html> drives the #vsbar-status-dot color (see app.css).
const applySocketState = (state) => {
  document.documentElement.dataset.socket = state
}
liveSocket.socket.onOpen(() => applySocketState("connected"))
liveSocket.socket.onClose(() => applySocketState("disconnected"))
liveSocket.socket.onError(() => applySocketState("disconnected"))
{
  const portEl = document.getElementById("vsbar-status-port")
  if (portEl) {
    const port = location.port || (location.protocol === "https:" ? "443" : "80")
    portEl.textContent = `:${port}`
  }
}

// VimNav is mounted directly (not via phx-hook) because Phoenix doesn't
// call mounted() for hooks on live layout elements.
// Keep the instance alive across LiveView navigations — destroying + re-creating
// on every phx:page-loading-stop briefly removes the keydown listener and breaks
// vim mode after history.back/forward. Only re-init when the enabled state on
// #vim-nav-root flips, so toggling vim_nav_enabled in Settings still takes effect
// on the next LiveView render without a hard reload.
let _vimNavInst = null
function _mountVimNav() {
  const el = document.getElementById("vim-nav-root")
  if (!el) return
  const enabled = el.dataset.vimNavEnabled === "true"

  if (_vimNavInst) {
    if (_vimNavInst._wasEnabled === enabled) return
    _vimNavInst._phxEventListeners?.forEach(({ event, handler }) =>
      window.removeEventListener(event, handler)
    )
    _vimNavInst.destroyed()
    _vimNavInst = null
  }

  if (!enabled) return

  const inst = Object.create(VimNav)
  inst.el = el
  inst._wasEnabled = enabled
  inst._phxEventListeners = []
  inst.pushEvent = (event, payload) => liveSocket.main?.pushHookEvent(el, el, event, payload)
  inst.pushEventToShell = (event, payload) => {
    const rail = document.getElementById("app-rail")
    if (!rail) return
    liveSocket.main?.pushHookEvent(rail, rail, event, payload)
  }
  inst.pushToList = (event, payload) => {
    const listEl = document.querySelector("[data-vim-list]")
    if (!listEl) return
    liveSocket.main?.pushHookEvent(listEl, listEl, event, payload)
  }
  inst.handleEvent = (event, callback) => {
    const handler = (e) => callback(e.detail)
    window.addEventListener(`phx:${event}`, handler)
    inst._phxEventListeners.push({ event: `phx:${event}`, handler })
  }
  inst.mounted()
  _vimNavInst = inst
}
window.addEventListener("phx:page-loading-stop", _mountVimNav)

// Intercept flyout canvas-session links before LiveView navigation fires.
// If the clicked session is already on the current canvas, dispatch canvas:focus-session
// directly (no server round-trip, no re-render). Otherwise let LiveView navigate normally.
document.addEventListener('click', (e) => {
  const link = e.target.closest('[data-focus-canvas-id]')
  if (!link) return
  const canvasArea = document.querySelector('[data-canvas-area]')
  if (!canvasArea) return
  const activeId = canvasArea.dataset.activeCanvasId
  const targetId = link.dataset.focusCanvasId
  if (activeId && String(activeId) === String(targetId)) {
    e.preventDefault()
    e.stopImmediatePropagation()
    window.dispatchEvent(new CustomEvent('canvas:focus-session', {
      detail: { sessionId: parseInt(link.dataset.focusSessionId, 10) }
    }))
  }
}, true) // capture phase — runs before LiveView's own click handler

// Tauri window drag: wry's built-in data-tauri-drag-region detection may not
// fire for external-URL webviews. We implement it explicitly: mousedown on
// any [data-tauri-drag-region] element (excluding interactive children) calls
// start_dragging. Requires core:window:allow-start-dragging in capabilities.
if (window.__TAURI_INTERNALS__) {
  document.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return
    const dragEl = e.composedPath().find(el =>
      el instanceof Element && el.hasAttribute('data-tauri-drag-region')
    )
    if (!dragEl) return
    // Don't drag if the actual target is an interactive element
    const interactive = e.target.closest('a, button, input, select, textarea, [contenteditable], [role="button"], summary')
    if (interactive) return
    window.__TAURI_INTERNALS__.invoke('plugin:window|start_dragging').catch(() => {})
  })
}

// Tauri file drop forwarding lives in the DragUpload hook (hooks/drag_upload.js)
// — hooks are the only public API for pushing events to a LiveView.
// The phx:pick_folder and tauri:rail-action bridges live in the RailState
// hook (hooks/rail_state.js) for the same reason: the previous app.js relays
// called view.pushEventTo, which does not exist on LiveView's View class, so
// every event was dropped silently (project creation via the native folder
// picker was a no-op through v0.3.9).

// --- Tauri command bridges ---------------------------------------------------
// LiveView pushes these events via push_event/3 when it needs a native dialog
// or a new window — the server can't open a dialog or window directly.
if (window.__TAURI_INTERNALS__) {
  const invoke = (cmd, args) => window.__TAURI_INTERNALS__.invoke(cmd, args ?? {})

  // phx:open_in_window — opens path in a new app window.
  // Payload: { path: "/projects/3" }
  window.addEventListener('phx:open_in_window', (e) => {
    const path = e.detail?.path ?? '/'
    invoke('open_window', { path })
  })

  // --- vsbar: always-on-top pin ---------------------------------------------
  // Revealed by CSS only under data-env="tauri". State lives in the Rust
  // shell's ALWAYS_ON_TOP static (shared with the menu/tray toggles).
  const pin = document.getElementById('vsbar-pin')
  if (pin) {
    invoke('get_always_on_top')
      .then((on) => pin.setAttribute('aria-pressed', String(!!on)))
      .catch(() => {})
    pin.addEventListener('click', () => {
      const next = pin.getAttribute('aria-pressed') !== 'true'
      invoke('set_always_on_top', { on: next })
        .then((actual) => pin.setAttribute('aria-pressed', String(!!actual)))
        .catch(() => {})
    })
  }

  // Session/project/file context menus are the web-rendered CtxMenu hook now
  // (browser + desktop parity) — the native show_session_context_menu path
  // is retired. tauri:rail-action handling lives in the RailState hook — see
  // note above.
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

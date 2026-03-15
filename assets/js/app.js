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
import {FavoriteFab} from "./hooks/favorite_fab"
import {ScrollToBottom} from "./hooks/scroll_to_bottom"
import {AutoScroll} from "./hooks/auto_scroll"
import {MarkdownMessage} from "./hooks/markdown_message"
import {CommandHistory} from "./hooks/command_history"
import {DiffViewer} from "./hooks/diff_viewer"
import {PasskeyAuth} from "./hooks/passkey_auth"
import {InfiniteScroll} from "./hooks/infinite_scroll"
import {DmComposer} from "./hooks/dm_composer"
import {FileAttach} from "./hooks/file_attach"
import {PushSetup} from "./push_notifications"
import {TOUCH_DEVICE, createSwipeDetector} from "./hooks/touch_gesture"
import {getHooks} from "live_svelte"
import "./theme"
import hljs from 'highlight.js'
import Sortable from 'sortablejs'
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

const debounce = (fn, wait = 120) => {
  let timeoutId
  const wrapped = (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn(...args), wait)
  }
  wrapped.cancel = () => clearTimeout(timeoutId)
  return wrapped
}

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
Hooks.FavoriteFab = FavoriteFab
Hooks.ScrollToBottom = ScrollToBottom
Hooks.AutoScroll = AutoScroll
Hooks.CommandHistory = CommandHistory
Hooks.MarkdownMessage = MarkdownMessage
Hooks.DiffViewer = DiffViewer
Hooks.PasskeyAuth = PasskeyAuth
Hooks.PushSetup = PushSetup
Hooks.InfiniteScroll = InfiniteScroll
Hooks.DmComposer = DmComposer
Hooks.FileAttach = FileAttach
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
Hooks.SortableKanban = {
  mounted() { this._init() },
  updated() {
    // Sortable handles DOM mutations internally; no need to destroy/recreate
  },
  _init() {
    const isTouchDevice = "ontouchstart" in window || navigator.maxTouchPoints > 0
    this.sortable = Sortable.create(this.el, {
      group: "kanban",
      animation: 150,
      ghostClass: "opacity-30",
      draggable: "[data-task-id]",
      handle: isTouchDevice ? "[data-drag-handle]" : null,
      delay: isTouchDevice ? 150 : 0,
      delayOnTouchOnly: true,
      touchStartThreshold: 5,
      onEnd: (evt) => {
        const taskId = evt.item.dataset.taskId
        const targetCol = evt.to.closest("[data-state-id]")
        const sourceCol = evt.from.closest("[data-state-id]")
        if (!taskId || !targetCol) return

        // Remove "No tasks" placeholder from target column immediately
        const placeholder = evt.to.querySelector("[data-empty-placeholder]")
        if (placeholder) placeholder.remove()

        const targetStateId = targetCol.dataset.stateId
        const movedColumn = targetCol !== sourceCol

        // Always send reorder for the target column
        const targetOrder = [...evt.to.querySelectorAll("[data-task-id]")].map(el => el.dataset.taskId)

        if (movedColumn) {
          // Column change: move_task handles state update, reorder handles position
          this.pushEvent("move_task", { task_id: taskId, state_id: targetStateId })
          if (targetOrder.length > 0) {
            this.pushEvent("reorder_tasks", { task_ids: targetOrder, state_id: targetStateId })
          }
          // Also reorder the source column
          const sourceOrder = [...evt.from.querySelectorAll("[data-task-id]")].map(el => el.dataset.taskId)
          if (sourceOrder.length > 0) {
            this.pushEvent("reorder_tasks", { task_ids: sourceOrder, state_id: sourceCol.dataset.stateId })
          }
        } else {
          // Same column: just reorder
          if (targetOrder.length > 0) {
            this.pushEvent("reorder_tasks", { task_ids: targetOrder, state_id: targetStateId })
          }
        }
      }
    })
  },
  destroyed() {
    if (this.sortable) this.sortable.destroy()
  }
}
Hooks.SortableColumns = {
  mounted() {
    this.sortable = Sortable.create(this.el, {
      animation: 150,
      ghostClass: "opacity-30",
      handle: "[data-column-handle]",
      draggable: "[data-column-id]",
      onEnd: () => {
        const order = [...this.el.querySelectorAll("[data-column-id]")].map(el => el.dataset.columnId)
        this.pushEvent("reorder_columns", { column_ids: order })
      }
    })
  },
  destroyed() {
    if (this.sortable) this.sortable.destroy()
  }
}
Hooks.KanbanKeyboard = {
  mounted() {
    this._handler = (e) => {
      // Skip if user is typing in an input/textarea/select
      const tag = e.target.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || e.target.isContentEditable) return

      if (e.key === "n" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        this.pushEvent("toggle_new_task_drawer", {})
      } else if (e.key === "/" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        const searchInput = this.el.querySelector("input[name='query']")
        if (searchInput) searchInput.focus()
      } else if (e.key === "Escape") {
        // Close drawers/quick-add if open
        const detailDrawer = document.getElementById("task-detail-panel")
        const newTaskDrawer = document.getElementById("new-task-drawer")
        if (detailDrawer) {
          this.pushEvent("toggle_task_detail_drawer", {})
        } else if (newTaskDrawer && newTaskDrawer.querySelector("[data-show='true']")) {
          this.pushEvent("toggle_new_task_drawer", {})
        } else {
          this.pushEvent("hide_quick_add", {})
        }
      }
    }
    document.addEventListener("keydown", this._handler)
  },
  destroyed() {
    if (this._handler) document.removeEventListener("keydown", this._handler)
  }
}
Hooks.KanbanScrollDots = {
  mounted() {
    const dots = this.el.querySelector("#kanban-dots")
    if (!dots) return
    const allDots = dots.querySelectorAll("[data-dot-index]")
    const count = parseInt(this.el.dataset.columnCount) || 0
    if (count === 0) return

    const update = () => {
      const scrollLeft = this.el.scrollLeft
      const scrollWidth = this.el.scrollWidth - this.el.clientWidth
      const ratio = scrollWidth > 0 ? scrollLeft / scrollWidth : 0
      const activeIdx = Math.round(ratio * (count - 1))
      allDots.forEach(dot => {
        const idx = parseInt(dot.dataset.dotIndex)
        dot.style.opacity = idx === activeIdx ? "1" : "0.3"
        dot.style.transform = idx === activeIdx ? "scale(1.3)" : "scale(1)"
      })
    }

    update()
    this.el.addEventListener("scroll", update, { passive: true })
    this._scrollHandler = update
  },
  destroyed() {
    if (this._scrollHandler) {
      this.el.removeEventListener("scroll", this._scrollHandler)
    }
  }
}
Hooks.LiveStreamToggle = {
  mounted() {
    const saved = localStorage.getItem("show_live_stream")
    if (saved === "true") {
      this.pushEvent("toggle_live_stream", {enabled: true})
    }
    this.el.addEventListener("click", () => {
      const current = localStorage.getItem("show_live_stream") === "true"
      localStorage.setItem("show_live_stream", String(!current))
    })
  }
}
Hooks.ModalDialog = {
  mounted() {
    this._sync()
    this._cancelHandler = (e) => {
      e.preventDefault()
      const toggleEvent = this.el.dataset.toggleEvent
      if (toggleEvent) this.pushEvent(toggleEvent, {})
    }
    this.el.addEventListener("cancel", this._cancelHandler)
  },
  destroyed() {
    this.el.removeEventListener("cancel", this._cancelHandler)
  },
  updated() { this._sync() },
  _sync() {
    const open = this.el.dataset.open === "true"
    if (open && !this.el.open) {
      this.el.showModal()
    } else if (!open && this.el.open) {
      this.el.close()
    }
  }
}
Hooks.GlobalKeydown = {
  mounted() {
    console.log("[GlobalKeydown] mounted on", this.el.id)
    this._handler = (e) => {
      if (e.ctrlKey && e.key === "k") {
        const tag = document.activeElement?.tagName
        if (tag === "INPUT" || tag === "TEXTAREA" || document.activeElement?.isContentEditable) return
        e.preventDefault()
        console.log("[GlobalKeydown] Ctrl+K fired, pushing event")
        this.pushEvent("keydown", {key: "k", ctrlKey: true})
      }
    }
    window.addEventListener("keydown", this._handler)
  },
  destroyed() {
    window.removeEventListener("keydown", this._handler)
  }
}
Hooks.LocalTime = {
  mounted() { this._format() },
  updated() { this._format() },
  _format() {
    const utc = this.el.dataset.utc
    if (!utc) return
    const d = new Date(utc)
    if (isNaN(d)) return
    if (this.el.dataset.fmt === 'short') {
      this.el.textContent = d.toLocaleString(undefined, {
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit'
      })
      return
    }
    const now = new Date()
    const yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    const timeStr = d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
    if (d.toDateString() === now.toDateString()) {
      this.el.textContent = `Today at ${timeStr}`
    } else if (d.toDateString() === yesterday.toDateString()) {
      this.el.textContent = `Yesterday at ${timeStr}`
    } else {
      this.el.textContent = d.toLocaleString(undefined, {
        month: '2-digit', day: '2-digit', year: 'numeric',
        hour: '2-digit', minute: '2-digit'
      })
    }
  }
}
Hooks.DragUpload = {
  mounted() {
    this._overlay = this.el.querySelector('#drag-overlay')
    this._active = false

    // Window-level listeners: more reliable for detecting when drag
    // enters/leaves the browser window vs element-boundary noise.
    this._onDragEnter = (e) => {
      const types = e.dataTransfer?.types
      if (!types) return
      if (!Array.from(types).includes('Files')) return
      if (!this._active) {
        this._active = true
        this._overlay?.classList.remove('hidden')
      }
    }

    this._onDragLeave = (e) => {
      // relatedTarget is null only when the cursor leaves the browser window
      if (e.relatedTarget === null) {
        this._active = false
        this._overlay?.classList.add('hidden')
      }
    }

    this._onDrop = () => {
      this._active = false
      this._overlay?.classList.add('hidden')
    }

    window.addEventListener('dragenter', this._onDragEnter)
    window.addEventListener('dragleave', this._onDragLeave)
    window.addEventListener('drop', this._onDrop)
  },
  destroyed() {
    window.removeEventListener('dragenter', this._onDragEnter)
    window.removeEventListener('dragleave', this._onDragLeave)
    window.removeEventListener('drop', this._onDrop)
  }
}
Hooks.SidebarState = {
  mounted() {
    // Restore collapsed state
    const savedCollapsed = localStorage.getItem("sidebar_collapsed")
    if (savedCollapsed === "true" && window.matchMedia("(min-width: 768px)").matches) {
      this.pushEventTo(this.el, "toggle_collapsed", {})
    }

    // Apply project expansion state immediately from localStorage (no server round-trip)
    this._applyExpandedProjects()

    // Handle project toggle buttons (delegated click on sidebar)
    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-project-toggle]")
      if (!btn) return
      const id = btn.dataset.projectToggle
      this._toggleProject(id)
    })

    this._projectFilterInput = this.el.querySelector("[data-project-filter]")
    this._debouncedProjectFilter = debounce((value) => this._applyProjectFilter(value), 120)
    this._projectFilterHandler = (e) => {
      this._debouncedProjectFilter(e.target.value || "")
    }
    this._projectFilterKeydown = (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        this._navigateToFirstVisibleProject()
      } else if (e.key === "Escape") {
        e.preventDefault()
        e.target.value = ""
        this._applyProjectFilter("")
      } else if (e.key === "ArrowDown") {
        const firstVisible = this._firstVisibleProjectLink()
        if (firstVisible) {
          e.preventDefault()
          firstVisible.focus()
        }
      }
    }
    if (this._projectFilterInput) {
      this._projectFilterInput.addEventListener("input", this._projectFilterHandler)
      this._projectFilterInput.addEventListener("keydown", this._projectFilterKeydown)
    }

    // Listen for mobile open event dispatched from the top bar outside this component
    this._openHandler = () => this.pushEventTo(this.el, "open_mobile", {})
    this.el.addEventListener("sidebar:open", this._openHandler)

    // Touch gestures — mobile only
    if (TOUCH_DEVICE) {
      // Swipe left on the open sidebar → close
      this._sidebarGesture = createSwipeDetector({
        onSwipeLeft: () => this.pushEventTo(this.el, "close_mobile", {}),
      })
      this.el.addEventListener("touchstart", this._sidebarGesture.onTouchStart, { passive: true })
      this.el.addEventListener("touchmove", this._sidebarGesture.onTouchMove, { passive: true })
      this.el.addEventListener("touchend", this._sidebarGesture.onTouchEnd, { passive: true })

      // Edge swipe right via dedicated grab handle → open sidebar.
      // #sidebar-grab-handle has touch-action:none so Safari's native back
      // gesture won't intercept touches that start on it.
      this._edgeGesture = createSwipeDetector({
        onSwipeRight: () => this.pushEventTo(this.el, "open_mobile", {}),
      })
      this._grabHandle = document.getElementById("sidebar-grab-handle")
      if (this._grabHandle) {
        this._grabHandle.addEventListener("touchstart", this._edgeGesture.onTouchStart)
        this._grabHandle.addEventListener("touchmove", this._edgeGesture.onTouchMove)
        this._grabHandle.addEventListener("touchend", this._edgeGesture.onTouchEnd)
      }
    }
  },

  updated() {
    // After LiveView re-renders (e.g. active project changed), reapply expansion state
    // and ensure the active project is expanded
    const activeId = this.el.dataset.activeProjectId
    if (activeId) {
      const expanded = this._getExpanded()
      if (!expanded.has(activeId)) {
        expanded.add(activeId)
        this._saveExpanded(expanded)
      }
    }
    this._applyExpandedProjects()
    const filterValue = this._projectFilterInput?.value || ""
    this._applyProjectFilter(filterValue)
  },

  _getExpanded() {
    try {
      const saved = localStorage.getItem("sidebar_expanded_projects")
      return new Set(saved ? JSON.parse(saved) : [])
    } catch (_) {
      return new Set()
    }
  },

  _saveExpanded(set) {
    localStorage.setItem("sidebar_expanded_projects", JSON.stringify([...set]))
  },

  _toggleProject(id) {
    const expanded = this._getExpanded()
    if (expanded.has(id)) {
      expanded.delete(id)
    } else {
      expanded.add(id)
    }
    this._saveExpanded(expanded)
    this._applyProject(id, expanded.has(id))
  },

  _applyExpandedProjects() {
    const expanded = this._getExpanded()

    // Also auto-expand the active project
    const activeId = this.el.dataset.activeProjectId
    if (activeId) {
      expanded.add(activeId)
      this._saveExpanded(expanded)
    }

    this.el.querySelectorAll("[data-project-id]").forEach(el => {
      const id = el.dataset.projectId
      this._applyProject(id, expanded.has(id))
    })
  },

  _applyProject(id, isExpanded) {
    const sub = document.getElementById(`project-sub-${id}`)
    const chevron = this.el.querySelector(`[data-project-chevron="${id}"]`)
    const toggle = this.el.querySelector(`[data-project-toggle="${id}"]`)
    if (sub) sub.style.display = isExpanded ? "" : "none"
    if (toggle) toggle.setAttribute("aria-expanded", isExpanded ? "true" : "false")
    if (chevron) {
      chevron.innerHTML = isExpanded
        ? `<svg class="w-3.5 h-3.5 flex-shrink-0" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" /></svg>`
        : `<svg class="w-3.5 h-3.5 flex-shrink-0" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" /></svg>`
    }
  },

  _applyProjectFilter(rawValue) {
    const query = rawValue.trim().toLowerCase()
    this.el.querySelectorAll("[data-project-id]").forEach((el) => {
      const name = (el.dataset.projectName || "").toLowerCase()
      const visible = query === "" || name.includes(query)
      el.style.display = visible ? "" : "none"
    })
  },

  _firstVisibleProjectLink() {
    const candidates = this.el.querySelectorAll("[data-project-id]")
    for (const row of candidates) {
      if (row.style.display === "none") continue
      const link = row.querySelector("[data-project-link]")
      if (link) return link
    }
    return null
  },

  _navigateToFirstVisibleProject() {
    const link = this._firstVisibleProjectLink()
    if (link) window.location.assign(link.getAttribute("href"))
  },

  destroyed() {
    if (this._debouncedProjectFilter?.cancel) {
      this._debouncedProjectFilter.cancel()
    }
    if (this._projectFilterInput && this._projectFilterHandler) {
      this._projectFilterInput.removeEventListener("input", this._projectFilterHandler)
    }
    if (this._projectFilterInput && this._projectFilterKeydown) {
      this._projectFilterInput.removeEventListener("keydown", this._projectFilterKeydown)
    }
    if (this._openHandler) {
      this.el.removeEventListener("sidebar:open", this._openHandler)
    }
    if (this._sidebarGesture) {
      this.el.removeEventListener("touchstart", this._sidebarGesture.onTouchStart)
      this.el.removeEventListener("touchmove", this._sidebarGesture.onTouchMove)
      this.el.removeEventListener("touchend", this._sidebarGesture.onTouchEnd)
    }
    if (this._grabHandle && this._edgeGesture) {
      this._grabHandle.removeEventListener("touchstart", this._edgeGesture.onTouchStart)
      this._grabHandle.removeEventListener("touchmove", this._edgeGesture.onTouchMove)
      this._grabHandle.removeEventListener("touchend", this._edgeGesture.onTouchEnd)
    }
  }
}

// Swipe-left-to-close for right-side drawer panels.
// Attach phx-hook="DrawerSwipeClose" and data-close-event="<event_name>" to the panel element.
Hooks.DrawerSwipeClose = {
  mounted() {
    if (!TOUCH_DEVICE) return
    const closeEvent = this.el.dataset.closeEvent
    if (!closeEvent) return
    this._gesture = createSwipeDetector({
      onSwipeLeft: () => this.pushEvent(closeEvent, {}),
    })
    this.el.addEventListener("touchstart", this._gesture.onTouchStart, { passive: true })
    this.el.addEventListener("touchmove", this._gesture.onTouchMove, { passive: true })
    this.el.addEventListener("touchend", this._gesture.onTouchEnd, { passive: true })
  },
  destroyed() {
    if (!this._gesture) return
    this.el.removeEventListener("touchstart", this._gesture.onTouchStart)
    this.el.removeEventListener("touchmove", this._gesture.onTouchMove)
    this.el.removeEventListener("touchend", this._gesture.onTouchEnd)
  },
}

// ---------------------------------------------------------------------------
// QuickCreateNote — global note creation dialog, triggered by palette:create-note
// ---------------------------------------------------------------------------

Hooks.QuickCreateNote = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qcn-title]")?.focus()
    }
    window.addEventListener("palette:create-note", this._openHandler)

    this.el.querySelector("[data-qcn-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qcn-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-note", this._openHandler)
  },

  async _submit() {
    const title = (this.el.querySelector("[data-qcn-title]")?.value || "").trim()
    const body = (this.el.querySelector("[data-qcn-body]")?.value || "").trim()
    if (!title) return

    const payload = { title, body }

    try {
      const res = await fetch("/api/v1/notes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      })
      if (res.ok) {
        this.el.close()
        this._reset()
        showToast("Note created")
      } else {
        showToast("Failed to create note")
      }
    } catch (_) {
      showToast("Failed to create note")
    }
  },

  _reset() {
    const t = this.el.querySelector("[data-qcn-title]")
    const b = this.el.querySelector("[data-qcn-body]")
    if (t) t.value = ""
    if (b) b.value = ""
  }
}

// ---------------------------------------------------------------------------
// QuickCreateAgent — spawn a new agent, triggered by palette:create-agent
// ---------------------------------------------------------------------------

Hooks.QuickCreateAgent = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qca-instructions]")?.focus()
    }
    window.addEventListener("palette:create-agent", this._openHandler)

    this.el.querySelector("[data-qca-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qca-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-agent", this._openHandler)
  },

  async _submit() {
    const instructions = (this.el.querySelector("[data-qca-instructions]")?.value || "").trim()
    if (!instructions) return

    const model = this.el.querySelector("[data-qca-model]")?.value || "haiku"
    const projectId = this.el.dataset.projectId ? Number(this.el.dataset.projectId) : null

    const body = { instructions, model }
    if (projectId) body.project_id = projectId

    try {
      const res = await fetch("/api/v1/agents", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
      if (res.ok) {
        const data = await res.json()
        this.el.close()
        this._reset()
        window.location.assign("/dm/" + data.session_uuid)
      } else {
        showToast("Failed to spawn agent")
      }
    } catch (_) {
      showToast("Failed to spawn agent")
    }
  },

  _reset() {
    const i = this.el.querySelector("[data-qca-instructions]")
    const m = this.el.querySelector("[data-qca-model]")
    if (i) i.value = ""
    if (m) m.value = "haiku"
  }
}

// ---------------------------------------------------------------------------
// QuickCreateChat — create a session and navigate to DM, triggered by palette:create-chat
// ---------------------------------------------------------------------------

Hooks.QuickCreateChat = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qcc-name]")?.focus()
    }
    window.addEventListener("palette:create-chat", this._openHandler)

    this.el.querySelector("[data-qcc-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qcc-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-chat", this._openHandler)
  },

  async _submit() {
    const name = (this.el.querySelector("[data-qcc-name]")?.value || "").trim()
    const projectId = this.el.dataset.projectId ? Number(this.el.dataset.projectId) : null

    const sessionId = crypto.randomUUID()
    const body = { session_id: sessionId }
    if (name) body.name = name
    if (projectId) body.project_id = projectId

    try {
      const res = await fetch("/api/v1/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
      if (res.ok) {
        const data = await res.json()
        this.el.close()
        window.location.assign("/dm/" + data.uuid)
      } else {
        showToast("Failed to create chat")
      }
    } catch (_) {
      showToast("Failed to create chat")
    }
  }
}

// ---------------------------------------------------------------------------
// QuickCreateTask — global task creation dialog, triggered by palette:create-task
// ---------------------------------------------------------------------------

Hooks.QuickCreateTask = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qct-title]")?.focus()
    }
    window.addEventListener("palette:create-task", this._openHandler)

    this.el.querySelector("[data-qct-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qct-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-task", this._openHandler)
  },

  async _submit() {
    const title = (this.el.querySelector("[data-qct-title]")?.value || "").trim()
    if (!title) return

    const description = (this.el.querySelector("[data-qct-description]")?.value || "").trim()
    const tagsRaw = (this.el.querySelector("[data-qct-tags]")?.value || "").trim()
    const tags = tagsRaw ? tagsRaw.split(",").map(t => t.trim()).filter(Boolean) : []
    const projectId = this.el.dataset.projectId ? Number(this.el.dataset.projectId) : null

    const body = { title, description, tags, state_id: 1 }
    if (projectId) body.project_id = projectId

    try {
      const res = await fetch("/api/v1/tasks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
      if (res.ok) {
        this.el.close()
        this._reset()
        showToast("Task created")
      } else {
        showToast("Failed to create task")
      }
    } catch (_) {
      showToast("Failed to create task")
    }
  },

  _reset() {
    const t = this.el.querySelector("[data-qct-title]")
    const d = this.el.querySelector("[data-qct-description]")
    const g = this.el.querySelector("[data-qct-tags]")
    if (t) t.value = ""
    if (d) d.value = ""
    if (g) g.value = ""
  }
}

// ---------------------------------------------------------------------------
// CommandRegistry — flat discriminated union of all palette commands
// ---------------------------------------------------------------------------

function getCommands() {
  return [
    // --- Workspace navigation ---
    { id: "go-sessions",      label: "Sessions",      icon: "hero-cpu-chip",                  group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/",              when: null },
    { id: "go-tasks",         label: "Tasks",         icon: "hero-clipboard-document-list",   group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/tasks",          when: null },
    { id: "go-notes",         label: "Notes",         icon: "hero-document-text",             group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/notes",          when: null },
    { id: "go-usage",         label: "Usage",         icon: "hero-chart-bar",                 group: "Insights",  hint: "Insights",  keywords: ["analytics", "stats"],    shortcut: null, type: "navigate", href: "/usage",          when: null },
    { id: "go-prompts",       label: "Prompts",       icon: "hero-book-open",                 group: "Knowledge", hint: "Knowledge", keywords: [],                        shortcut: null, type: "navigate", href: "/prompts",        when: null },
    { id: "go-skills",        label: "Skills",        icon: "hero-bolt",                      group: "Knowledge", hint: "Knowledge", keywords: [],                        shortcut: null, type: "navigate", href: "/skills",         when: null },
    { id: "go-notifications", label: "Notifications", icon: "hero-bell",                      group: "Knowledge", hint: "Knowledge", keywords: ["alerts"],                shortcut: null, type: "navigate", href: "/notifications",  when: null },
    { id: "go-jobs",          label: "Jobs",          icon: "hero-cog-6-tooth",               group: "System",    hint: "System",    keywords: ["scheduled", "cron"],     shortcut: null, type: "navigate", href: "/jobs",           when: null },
    { id: "go-settings",      label: "Settings",      icon: "hero-adjustments-horizontal",    group: "System",    hint: "System",    keywords: ["config", "preferences"], shortcut: null, type: "navigate", href: "/settings",       when: null },

    // --- Actions ---
    {
      id: "create-task",
      label: "Create Task",
      icon: "hero-plus",
      group: "Tasks",
      hint: null,
      keywords: ["new", "add", "todo"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-task")) },
      when: null
    },
    {
      id: "create-note",
      label: "Create Note",
      icon: "hero-document-text",
      group: "Notes",
      hint: null,
      keywords: ["new", "add", "write", "memo"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-note")) },
      when: null
    },
    {
      id: "create-agent",
      label: "New Agent",
      icon: "hero-cpu-chip",
      group: "Agents",
      hint: null,
      keywords: ["spawn", "run", "claude", "ai", "bot"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-agent")) },
      when: null
    },
    {
      id: "create-chat",
      label: "New Chat",
      icon: "hero-chat-bubble-left-right",
      group: "Workspace",
      hint: null,
      keywords: ["session", "dm", "conversation", "talk"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:create-chat")) },
      when: null
    },
    {
      id: "toggle-theme",
      label: "Toggle Theme",
      icon: "hero-moon",
      group: "System",
      hint: null,
      keywords: ["dark", "light", "mode"],
      shortcut: null,
      type: "callback",
      fn: () => {
        const current = document.documentElement.getAttribute("data-theme") || localStorage.getItem("theme") || "light"
        const next = current === "dark" ? "light" : "dark"
        localStorage.setItem("theme", next)
        document.documentElement.setAttribute("data-theme", next)
        document.querySelectorAll(".theme-controller").forEach(c => {
          if (c.type === "checkbox") c.checked = next === "dark"
        })
      },
      when: null
    },
    {
      id: "copy-url",
      label: "Copy Current URL",
      icon: "hero-link",
      group: "System",
      hint: null,
      keywords: ["clipboard", "share", "link"],
      shortcut: null,
      type: "callback",
      fn: () => {
        navigator.clipboard.writeText(window.location.href)
          .then(() => {
            window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
              detail: { text: window.location.href, format: "text/plain" }
            }))
          })
          .catch(() => {
            window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
              detail: { text: "", format: "text/plain", error: true }
            }))
          })
      },
      when: null
    },

    // --- Submenus ---
    {
      id: "list-sessions",
      label: "Go to Session...",
      icon: "hero-chat-bubble-left-right",
      group: "Workspace",
      hint: null,
      keywords: ["dm", "chat", "open", "history", "recent"],
      shortcut: null,
      type: "submenu",
      commands: async () => {
        try {
          const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
          const url = projectId
            ? `/api/v1/sessions?limit=30&status=all&project_id=${projectId}`
            : "/api/v1/sessions?limit=30&status=all"
          const res = await fetch(url)
          if (!res.ok) return []
          const data = await res.json()
          return (data.results || []).map(s => ({
            id: "session-" + s.uuid,
            label: s.description || s.uuid.slice(0, 8),
            icon: "hero-chat-bubble-left-right",
            group: projectId ? "Project Sessions" : "Recent",
            hint: s.status,
            keywords: [],
            shortcut: null,
            type: "navigate",
            href: "/dm/" + s.uuid,
            when: null
          }))
        } catch (_) { return [] }
      },
      when: null
    },
    {
      id: "go-project",
      label: "Go to Project...",
      icon: "hero-folder",
      group: "Projects",
      hint: null,
      keywords: ["open", "switch", "navigate"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        const registryHrefs = new Set(getCommands().map(c => c.href).filter(Boolean))
        return [...document.querySelectorAll("#app-sidebar a[href^='/projects/']")]
          .map(a => ({ label: (a.textContent || "").trim().replace(/\s+/g, " "), href: a.getAttribute("href") }))
          .filter(({ label, href }) => label && href && href !== "#" && !registryHrefs.has(href))
          .map(({ label, href }) => ({
            id: "go-project-" + href.replace(/[^a-z0-9]+/gi, "-").toLowerCase(),
            label,
            icon: "hero-folder",
            group: "Projects",
            hint: "Projects",
            keywords: [],
            shortcut: null,
            type: "navigate",
            href,
            when: null
          }))
      },
      when: null
    }
  ]
}

Hooks.CommandPalette = {
  mounted() {
    this.input = this.el.querySelector("[data-palette-input]")
    this.results = this.el.querySelector("[data-palette-results]")
    this.breadcrumb = this.el.querySelector("[data-palette-breadcrumb]")
    this.stack = []
    this.activeIndex = 0
    this.visibleItems = []

    this._isMac = navigator.userAgentData
      ? navigator.userAgentData.platform === "macOS"
      : navigator.platform.toUpperCase().includes("MAC")

    this._globalKeyHandler = (e) => {
      if ((this._isMac ? e.metaKey : e.ctrlKey) && e.key.toLowerCase() === "k") {
        const inEditor = document.activeElement?.closest(".cm-editor, .monaco-editor, [data-palette-no-intercept]")
        if (inEditor) return
        e.preventDefault()
        this.open()
      }
    }
    window.addEventListener("keydown", this._globalKeyHandler)

    this._openHandler = () => this.open()
    this.el.addEventListener("palette:open", this._openHandler)

    this.input?.addEventListener("input", () => {
      this.activeIndex = 0
      this.render()
    })
    this.input?.addEventListener("keydown", (e) => this.onInputKeydown(e))

    this._resultsClickHandler = (e) => {
      const btn = e.target.closest("button[data-index]")
      if (!btn) return
      const idx = Number(btn.dataset.index)
      const cmd = this.visibleItems[idx]
      if (cmd) this.activate(cmd)
    }
    this.results?.addEventListener("click", this._resultsClickHandler)
  },

  destroyed() {
    window.removeEventListener("keydown", this._globalKeyHandler)
    this.el.removeEventListener("palette:open", this._openHandler)
    this.results?.removeEventListener("click", this._resultsClickHandler)
  },

  open() {
    this.stack = []
    this.activeIndex = 0
    this.el.showModal()
    if (this.input) {
      this.input.value = ""
      this.input.focus()
    }
    this.updateBreadcrumb()
    this.render()
  },

  activeCommands() {
    if (this.stack.length === 0) return getCommands()
    return this.stack[this.stack.length - 1].commands
  },

  filteredItems() {
    const q = (this.input?.value || "").trim().toLowerCase()
    const cmds = this.activeCommands().filter(cmd => !cmd.when || cmd.when())

    if (!q) {
      if (this.stack.length === 0) {
        const recent = this.loadRecent()
        const byHref = new Map(cmds.filter(c => c.type === "navigate").map(c => [c.href, c]))
        const recentItems = recent
          .map(r => byHref.get(r.href))
          .filter(Boolean)
          .filter(cmd => !cmd.when || cmd.when())
        const recentHrefs = new Set(recentItems.map(c => c.href))
        const rest = cmds.filter(c => !recentHrefs.has(c.href))
        return [...recentItems, ...rest].slice(0, 40)
      }
      return cmds.slice(0, 40)
    }

    return cmds
      .map(cmd => {
        const positions = this.fuzzyPositions(cmd.label, q)
        return { cmd, score: this.scoreCmd(cmd, q, positions), positions }
      })
      .filter(({ score }) => score > 0)
      .sort((a, b) => b.score - a.score || a.cmd.label.localeCompare(b.cmd.label))
      .slice(0, 40)
      .map(({ cmd, positions }) => ({ ...cmd, _matchPositions: positions }))
  },

  scoreCmd(cmd, q, positions) {
    const label = cmd.label.toLowerCase()
    let score = 0

    if (label === q) score += 200
    if (label.startsWith(q)) score += 100
    if (label.includes(q)) score += 50

    if (positions !== null) {
      score += 60
      let consecutive = 0
      for (let i = 1; i < positions.length; i++) {
        if (positions[i] === positions[i - 1] + 1) consecutive++
      }
      score += consecutive * 2
    }

    const kws = (cmd.keywords || []).join(" ").toLowerCase()
    if (kws && kws.includes(q)) score += 30
    if (cmd.hint && cmd.hint.toLowerCase().includes(q)) score += 15
    if (cmd.group && cmd.group.toLowerCase().includes(q)) score += 10

    return score
  },

  fuzzyPositions(label, q) {
    const lc = label.toLowerCase()
    const positions = []
    let qi = 0
    for (let i = 0; i < lc.length && qi < q.length; i++) {
      if (lc[i] === q[qi]) { positions.push(i); qi++ }
    }
    return qi === q.length ? positions : null
  },

  render() {
    if (!this.results) return
    const items = this.filteredItems()
    this.visibleItems = items
    if (this.activeIndex >= items.length) this.activeIndex = 0

    if (items.length === 0) {
      this.results.innerHTML = `<div class="px-3 py-4 text-sm text-base-content/50">No matches</div>`
      return
    }

    const q = (this.input?.value || "").trim()
    const grouped = !q && this.stack.length === 0

    this.results.innerHTML = grouped ? this.renderGrouped(items) : this.renderFlat(items)

    const active = this.results.querySelector(`button[data-index="${this.activeIndex}"]`)
    if (active) active.scrollIntoView({ block: "nearest" })
  },

  renderGrouped(items) {
    const groupOrder = ["Workspace", "Projects", "Tasks", "Insights", "Knowledge", "Communication", "System"]
    const groups = new Map()
    for (const item of items) {
      const g = item.group || "Other"
      if (!groups.has(g)) groups.set(g, [])
      groups.get(g).push(item)
    }

    let idx = 0
    return [...groups.entries()]
      .sort((a, b) => {
        const ai = groupOrder.indexOf(a[0])
        const bi = groupOrder.indexOf(b[0])
        return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi) || a[0].localeCompare(b[0])
      })
      .map(([group, groupItems]) => {
        const buttons = groupItems.map(item => this.renderRow(item, idx++, null)).join("")
        return `<section class="px-1 py-1"><h3 class="px-2 py-1 text-[10px] uppercase tracking-wider text-base-content/40">${this.escapeHtml(group)}</h3><div>${buttons}</div></section>`
      }).join("")
  },

  renderFlat(items) {
    return `<div class="px-1 py-1">${items.map((item, i) => this.renderRow(item, i, item._matchPositions || null)).join("")}</div>`
  },

  renderRow(item, idx, matchPositions) {
    const isActive = idx === this.activeIndex
    const labelHtml = matchPositions
      ? this.highlightLabel(item.label, new Set(matchPositions))
      : this.escapeHtml(item.label)

    const hintHtml = item.hint
      ? `<div class="text-xs text-base-content/45 truncate">${this.escapeHtml(item.hint)}</div>`
      : ""

    const shortcutHtml = item.shortcut
      ? item.shortcut.split(" ").map(k => `<kbd class="text-[10px] px-1 py-0.5 rounded border border-base-content/20 text-base-content/50">${this.escapeHtml(k)}</kbd>`).join(" ")
      : ""

    const chevronHtml = item.type === "submenu"
      ? `<span class="hero-chevron-right w-3 h-3 text-base-content/40 shrink-0"></span>`
      : ""

    const rightHtml = (shortcutHtml || chevronHtml)
      ? `<div class="flex items-center gap-1 ml-2 shrink-0">${shortcutHtml}${chevronHtml}</div>`
      : ""

    return `<button type="button" data-index="${idx}" role="option" aria-selected="${isActive}" class="w-full text-left rounded-lg px-3 py-2 text-sm flex items-center gap-2 transition-colors ${isActive ? "bg-base-200 text-base-content" : "hover:bg-base-200/70 text-base-content/80"}"><span class="${this.escapeHtml(item.icon)} w-4 h-4 shrink-0 text-base-content/50"></span><div class="flex-1 min-w-0"><div class="font-medium truncate">${labelHtml}</div>${hintHtml}</div>${rightHtml}</button>`
  },

  highlightLabel(label, matchedPositions) {
    return [...label].map((char, i) =>
      matchedPositions.has(i)
        ? `<mark class="bg-transparent text-primary font-semibold">${this.escapeHtml(char)}</mark>`
        : this.escapeHtml(char)
    ).join("")
  },

  updateBreadcrumb() {
    if (!this.breadcrumb) return
    if (this.stack.length === 0) {
      this.breadcrumb.classList.add("hidden")
      this.breadcrumb.textContent = ""
    } else {
      this.breadcrumb.classList.remove("hidden")
      this.breadcrumb.textContent = ["Commands", ...this.stack.map(s => s.label)].join(" › ")
    }
  },

  onInputKeydown(e) {
    const items = this.visibleItems || []
    const len = Math.max(items.length, 1)

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.activeIndex = (this.activeIndex + 1) % len
      this.render()
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.activeIndex = (this.activeIndex - 1 + len) % len
      this.render()
    } else if (e.key === "Enter") {
      e.preventDefault()
      const cmd = items[this.activeIndex]
      if (cmd) this.activate(cmd)
    } else if (e.key === "Escape") {
      e.preventDefault()
      if (this.stack.length > 0) {
        this.stack.pop()
        this.activeIndex = 0
        if (this.input) this.input.value = ""
        this.updateBreadcrumb()
        this.render()
      } else {
        this.el.close()
      }
    } else if (e.key === "Backspace" && !e.isComposing) {
      if ((this.input?.value || "") === "" && this.stack.length > 0) {
        e.preventDefault()
        this.stack.pop()
        this.activeIndex = 0
        this.updateBreadcrumb()
        this.render()
      }
    }
  },

  async activate(cmd) {
    if (cmd.type === "navigate") {
      this.saveRecent(cmd)
      this.el.close()
      window.location.assign(cmd.href)
    } else if (cmd.type === "callback") {
      this.el.close()
      cmd.fn()
    } else if (cmd.type === "submenu") {
      let commands = typeof cmd.commands === "function" ? cmd.commands() : cmd.commands
      this.activeIndex = 0
      if (this.input) this.input.value = ""
      if (commands instanceof Promise) {
        this.stack.push({ id: cmd.id, label: cmd.label, commands: [] })
        this.updateBreadcrumb()
        if (this.results) this.results.innerHTML = `<div class="px-3 py-4 text-sm text-base-content/50">Loading...</div>`
        commands = await commands
        this.stack[this.stack.length - 1].commands = commands
      } else {
        this.stack.push({ id: cmd.id, label: cmd.label, commands })
        this.updateBreadcrumb()
      }
      this.render()
    }
  },

  loadRecent() {
    try {
      const parsed = JSON.parse(localStorage.getItem("command_palette_recent") || "[]")
      return Array.isArray(parsed) ? parsed : []
    } catch (_) { return [] }
  },

  saveRecent(cmd) {
    if (cmd.type !== "navigate") return
    const existing = this.loadRecent().filter(e => e.href !== cmd.href)
    const next = [{ id: cmd.id, label: cmd.label, href: cmd.href, at: Date.now() }, ...existing].slice(0, 8)
    localStorage.setItem("command_palette_recent", JSON.stringify(next))
  },

  escapeHtml(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}

// Persist sidebar collapse state on toggle
window.addEventListener("click", (e) => {
  const btn = e.target.closest("[phx-click='toggle_collapsed']")
  if (btn) {
    const sidebar = document.getElementById("app-sidebar")
    if (sidebar) {
      // Toggle: if currently expanded on desktop, it's about to collapse
      const isCurrentlyExpanded = sidebar.classList.contains("md:w-60")
      localStorage.setItem("sidebar_collapsed", isCurrentlyExpanded ? "true" : "false")
    }
  }
})

Hooks.FlashTimeout = {
  mounted() {
    this._timer = setTimeout(() => {
      this.el.click()
    }, 5000)
  },
  destroyed() {
    clearTimeout(this._timer)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())
function showToast(message) {
  const toast = document.createElement("div")
  toast.className = "fixed bottom-4 right-4 z-[9999] bg-base-content text-base-100 text-xs font-medium px-4 py-2 rounded-lg shadow-lg opacity-0 transition-opacity duration-200"
  toast.textContent = message
  document.body.appendChild(toast)
  requestAnimationFrame(() => { toast.style.opacity = "1" })
  setTimeout(() => {
    toast.style.opacity = "0"
    setTimeout(() => toast.remove(), 200)
  }, 2000)
}

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

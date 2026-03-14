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
    this.sortable = Sortable.create(this.el, {
      group: "kanban",
      animation: 150,
      ghostClass: "opacity-30",
      draggable: "[data-task-id]",
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

Hooks.CommandPalette = {
  mounted() {
    this.input = this.el.querySelector("[data-palette-input]")
    this.results = this.el.querySelector("[data-palette-results]")
    this.items = []
    this.visibleItems = []
    this.activeIndex = 0

    this._openHandler = () => this.open()
    this.el.addEventListener("palette:open", this._openHandler)

    this._globalKeyHandler = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        this.open()
      }
    }
    window.addEventListener("keydown", this._globalKeyHandler)

    this._debouncedRender = debounce(() => this.render(), 90)
    this.input?.addEventListener("input", this._debouncedRender)
    this.input?.addEventListener("keydown", (e) => this.onInputKeydown(e))

    this._resultsClickHandler = (e) => {
      const btn = e.target.closest("button[data-index]")
      if (!btn) return
      const idx = Number(btn.dataset.index)
      this.navigate(this.visibleItems[idx])
    }
    this.results?.addEventListener("click", this._resultsClickHandler)
  },

  destroyed() {
    if (this._debouncedRender?.cancel) {
      this._debouncedRender.cancel()
    }
    this.input?.removeEventListener("input", this._debouncedRender)
    window.removeEventListener("keydown", this._globalKeyHandler)
    this.el.removeEventListener("palette:open", this._openHandler)
    this.results?.removeEventListener("click", this._resultsClickHandler)
  },

  open() {
    this.collectItems()
    this.activeIndex = 0
    this.el.showModal()
    if (this.input) {
      this.input.value = ""
      this.input.focus()
    }
    this.render()
  },

  collectItems() {
    const staticItems = [
      { label: "Sessions", href: "/", group: "Workspace" },
      { label: "Tasks", href: "/tasks", group: "Workspace" },
      { label: "Notes", href: "/notes", group: "Workspace" },
      { label: "Usage", href: "/usage", group: "Insights" },
      { label: "Prompts", href: "/prompts", group: "Knowledge" },
      { label: "Skills", href: "/skills", group: "Knowledge" },
      { label: "Notifications", href: "/notifications", group: "Knowledge" },
      { label: "Jobs", href: "/jobs", group: "System" },
      { label: "Settings", href: "/settings", group: "System" }
    ]

    const sidebarLinks = [...document.querySelectorAll("#app-sidebar a[href]")]
      .map((a) => ({
        label: (a.textContent || "").trim().replace(/\s+/g, " "),
        href: a.getAttribute("href")
      }))
      .filter((item) => item.label && item.href && item.href !== "#")
      .map((item) => ({
        ...item,
        group: this.groupForHref(item.href)
      }))

    const deduped = new Map()
    for (const item of [...staticItems, ...sidebarLinks]) {
      const key = `${item.label}|${item.href}`
      deduped.set(key, item)
    }
    this.items = [...deduped.values()]
  },

  filteredItems() {
    const q = (this.input?.value || "").trim().toLowerCase()
    if (!q) {
      const recent = this.loadRecent()
      const byHref = new Map(this.items.map((item) => [item.href, item]))
      const recentItems = recent
        .map((r) => byHref.get(r.href))
        .filter(Boolean)
      const seen = new Set(recentItems.map((item) => `${item.label}|${item.href}`))
      const rest = this.items.filter((item) => !seen.has(`${item.label}|${item.href}`))
      return [...recentItems, ...rest].slice(0, 40)
    }

    return this.items
      .map((item) => ({...item, _score: this.scoreItem(item, q)}))
      .filter((item) => item._score > 0)
      .sort((a, b) => b._score - a._score || a.label.localeCompare(b.label))
      .slice(0, 40)
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

    let idx = 0
    const grouped = this.groupItems(items)
    this.results.innerHTML = grouped.map((section) => {
      const buttons = section.items.map((item) => {
        const buttonIndex = idx
        idx += 1
        return `
          <button
            type="button"
            data-index="${buttonIndex}"
            role="option"
            aria-selected="${buttonIndex === this.activeIndex}"
            class="w-full text-left rounded-lg px-3 py-2.5 text-sm transition-colors ${buttonIndex === this.activeIndex ? "bg-base-200 text-base-content" : "hover:bg-base-200/70 text-base-content/80"}"
          >
            <div class="font-medium truncate">${this.escapeHtml(item.label)}</div>
            <div class="text-[11px] text-base-content/45 truncate">${this.escapeHtml(item.href)}</div>
          </button>
        `
      }).join("")

      return `
        <section class="px-1 py-1">
          <h3 class="px-2 py-1 text-[10px] uppercase tracking-wider text-base-content/40">${this.escapeHtml(section.group)}</h3>
          <div class="space-y-1">${buttons}</div>
        </section>
      `
    }).join("")

    const active = this.results.querySelector(`button[data-index="${this.activeIndex}"]`)
    if (active) active.scrollIntoView({block: "nearest"})
  },

  onInputKeydown(e) {
    const items = this.visibleItems
    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.activeIndex = Math.min(this.activeIndex + 1, Math.max(items.length - 1, 0))
      this.render()
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.activeIndex = Math.max(this.activeIndex - 1, 0)
      this.render()
    } else if (e.key === "Enter") {
      e.preventDefault()
      if (items[this.activeIndex]) this.navigate(items[this.activeIndex])
    } else if (e.key === "Escape") {
      this.el.close()
    }
  },

  navigate(item) {
    if (!item?.href) return
    this.saveRecent(item)
    window.location.assign(item.href)
  },

  groupForHref(href) {
    if (href.startsWith("/projects/")) return "Projects"
    if (href.startsWith("/chat")) return "Communication"
    if (href.startsWith("/settings") || href.startsWith("/jobs") || href.startsWith("/config")) return "System"
    if (href.startsWith("/usage")) return "Insights"
    if (href.startsWith("/prompts") || href.startsWith("/skills") || href.startsWith("/notes") || href.startsWith("/notifications")) return "Knowledge"
    return "Workspace"
  },

  groupItems(items) {
    const groupOrder = ["Workspace", "Projects", "Insights", "Knowledge", "Communication", "System"]
    const groups = new Map()
    for (const item of items) {
      const group = item.group || this.groupForHref(item.href)
      if (!groups.has(group)) groups.set(group, [])
      groups.get(group).push(item)
    }

    return [...groups.entries()]
      .sort((a, b) => {
        const aIndex = groupOrder.indexOf(a[0])
        const bIndex = groupOrder.indexOf(b[0])
        const left = aIndex === -1 ? 999 : aIndex
        const right = bIndex === -1 ? 999 : bIndex
        return left - right || a[0].localeCompare(b[0])
      })
      .map(([group, groupedItems]) => ({group, items: groupedItems}))
  },

  scoreItem(item, q) {
    const label = item.label.toLowerCase()
    const href = item.href.toLowerCase()
    let score = 0

    if (label === q) score += 120
    if (label.startsWith(q)) score += 90
    if (label.includes(q)) score += 50
    if (href.startsWith(q)) score += 35
    if (href.includes(q)) score += 20
    if (item.group && item.group.toLowerCase().includes(q)) score += 10

    return score
  },

  loadRecent() {
    try {
      const parsed = JSON.parse(localStorage.getItem("command_palette_recent") || "[]")
      return Array.isArray(parsed) ? parsed : []
    } catch (_) {
      return []
    }
  },

  saveRecent(item) {
    const now = Date.now()
    const existing = this.loadRecent().filter((entry) => entry.href !== item.href)
    const next = [{label: item.label, href: item.href, at: now}, ...existing].slice(0, 8)
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
window.addEventListener("phx:copy_to_clipboard", (e) => {
  const { text, format } = e.detail
  if (!text || !navigator.clipboard) return

  navigator.clipboard.writeText(text).then(() => {
    const toast = document.createElement("div")
    toast.className = "fixed bottom-4 right-4 z-[9999] bg-base-content text-base-100 text-xs font-medium px-4 py-2 rounded-lg shadow-lg opacity-0 transition-opacity duration-200"
    toast.textContent = `Copied as ${format}`
    document.body.appendChild(toast)
    requestAnimationFrame(() => { toast.style.opacity = "1" })
    setTimeout(() => {
      toast.style.opacity = "0"
      setTimeout(() => toast.remove(), 200)
    }, 2000)
  }).catch(err => console.error("Failed to copy:", err))
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

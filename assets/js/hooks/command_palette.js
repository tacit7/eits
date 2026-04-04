function getCommands(hook) {
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
      id: "update-agent",
      label: "Update Agent Instructions",
      icon: "hero-pencil-square",
      group: "Agents",
      hint: null,
      keywords: ["edit", "modify", "instructions", "agent"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:update-agent")) },
      when: null
    },
    {
      id: "get-agent",
      label: "Get Agent Details",
      icon: "hero-magnifying-glass",
      group: "Agents",
      hint: null,
      keywords: ["find", "search", "lookup", "agent", "uuid", "details"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:get-agent")) },
      when: null
    },
    {
      id: "delete-agent",
      label: "Delete Agent",
      icon: "hero-trash",
      group: "Agents",
      hint: null,
      keywords: ["remove", "delete", "destroy", "agent", "uuid"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:delete-agent")) },
      when: null
    },
    {
      id: "resume-agent",
      label: "Resume Agent",
      icon: "hero-play",
      group: "Agents",
      hint: null,
      keywords: ["resume", "restart", "continue", "spawn", "agent", "uuid"],
      shortcut: null,
      type: "callback",
      fn: () => { window.dispatchEvent(new CustomEvent("palette:resume-agent")) },
      when: null
    },
    {
      id: "list-agents",
      label: "List Agents...",
      icon: "hero-queue-list",
      group: "Agents",
      hint: null,
      keywords: ["view", "show", "all", "agents", "list"],
      shortcut: null,
      type: "submenu",
      commands: () => {
        if (!hook) return Promise.resolve([])
        const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
        return new Promise((resolve) => {
          hook._paletteAgentsResolve = resolve
          hook.pushEvent("palette:list-agents", { project_id: projectId })
          setTimeout(() => resolve([]), 2000)
        }).then(agents => agents.map(a => ({
          id: "agent-" + a.uuid,
          label: a.name,
          icon: "hero-cpu-chip",
          group: null,
          hint: `UUID: ${a.uuid} | Status: ${a.status} | Sessions: ${a.session_count}`,
          keywords: [],
          shortcut: null,
          type: "callback",
          fn: () => {
            // Copy agent UUID to clipboard
            navigator.clipboard.writeText(a.uuid)
              .then(() => {
                window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
                  detail: { text: a.uuid, format: "text/plain" }
                }))
              })
          },
          when: null
        })))
      },
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
      commands: () => {
        if (!hook) return Promise.resolve([])
        const projectId = document.getElementById("quick-create-task")?.dataset?.projectId
        return new Promise((resolve) => {
          hook._paletteSessionsResolve = resolve
          hook.pushEvent("palette:sessions", { project_id: projectId || null })
        }).then(sessions => sessions.map(s => ({
          id: "session-" + s.uuid,
          label: s.name || s.description || (s.uuid || "").slice(0, 8),
          icon: "hero-chat-bubble-left-right",
          group: projectId ? "Project Sessions" : "Recent",
          hint: s.status,
          keywords: [],
          shortcut: null,
          type: "navigate",
          href: "/dm/" + s.uuid,
          when: null
        })))
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
        const projects = JSON.parse(hook?.el?.dataset?.projects || "[]")
        return projects.map(p => ({
          id: "go-project-" + p.id,
          label: p.name,
          icon: "hero-folder",
          group: "Projects",
          hint: null,
          keywords: [],
          shortcut: null,
          type: "navigate",
          href: "/projects/" + p.id,
          when: null
        }))
      },
      when: null
    }
  ]
}

import { fuzzyPositions, scoreCmd, escapeHtml, highlightLabel } from "./palette_utils.js"

export const CommandPalette = {
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

    this.handleEvent("palette:sessions-result", ({ sessions }) => {
      if (this._paletteSessionsResolve) {
        this._paletteSessionsResolve(sessions)
        this._paletteSessionsResolve = null
      }
    })

    this.handleEvent("palette:list-agents-result", ({ agents }) => {
      if (this._paletteAgentsResolve) {
        this._paletteAgentsResolve(agents)
        this._paletteAgentsResolve = null
      }
    })

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
    if (this.stack.length === 0) return getCommands(this)
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
        const positions = fuzzyPositions(cmd.label, q)
        return { cmd, score: scoreCmd(cmd, q, positions), positions }
      })
      .filter(({ score }) => score > 0)
      .sort((a, b) => b.score - a.score || a.cmd.label.localeCompare(b.cmd.label))
      .slice(0, 40)
      .map(({ cmd, positions }) => ({ ...cmd, _matchPositions: positions }))
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
        return `<section class="px-1 py-1"><h3 class="px-2 py-1 text-[10px] uppercase tracking-wider text-base-content/40">${escapeHtml(group)}</h3><div>${buttons}</div></section>`
      }).join("")
  },

  renderFlat(items) {
    return `<div class="px-1 py-1">${items.map((item, i) => this.renderRow(item, i, item._matchPositions || null)).join("")}</div>`
  },

  renderRow(item, idx, matchPositions) {
    const isActive = idx === this.activeIndex
    const labelHtml = matchPositions
      ? highlightLabel(item.label, new Set(matchPositions))
      : escapeHtml(item.label)

    const hintHtml = item.hint
      ? `<div class="text-xs text-base-content/45 truncate">${escapeHtml(item.hint)}</div>`
      : ""

    const shortcutHtml = item.shortcut
      ? item.shortcut.split(" ").map(k => `<kbd class="text-[10px] px-1 py-0.5 rounded border border-base-content/20 text-base-content/50">${escapeHtml(k)}</kbd>`).join(" ")
      : ""

    const chevronHtml = item.type === "submenu"
      ? `<span class="hero-chevron-right w-3 h-3 text-base-content/40 shrink-0"></span>`
      : ""

    const rightHtml = (shortcutHtml || chevronHtml)
      ? `<div class="flex items-center gap-1 ml-2 shrink-0">${shortcutHtml}${chevronHtml}</div>`
      : ""

    return `<button type="button" data-index="${idx}" role="option" aria-selected="${isActive}" class="w-full text-left rounded-lg px-3 py-2 text-sm flex items-center gap-2 transition-colors ${isActive ? "bg-base-content/8 text-base-content" : "hover:bg-base-content/5 text-base-content/80"}"><span class="${escapeHtml(item.icon)} w-4 h-4 shrink-0 text-base-content/50"></span><div class="flex-1 min-w-0"><div class="font-medium truncate">${labelHtml}</div>${hintHtml}</div>${rightHtml}</button>`
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
    } else if (e.key === "Tab") {
      if (items.length === 1) {
        e.preventDefault()
        this.activate(items[0])
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

}

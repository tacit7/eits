import { fuzzyPositions, scoreCmd, escapeHtml, highlightLabel } from "./palette_utils.js"
import { getCommands } from "./palette_commands/index.js"

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

    // Read shortcut from root layout div (data-palette-shortcut) on each keydown
    // so live-navigation setting changes are picked up without remounting.
    // "auto" = Cmd OR Ctrl on Mac, Ctrl elsewhere; "cmd" = metaKey only;
    // "ctrl" = ctrlKey only; "alt" = altKey only
    this._matchesModifier = (e) => {
      const el = document.querySelector("[data-palette-shortcut]")
      const shortcut = el ? (el.dataset.paletteShortcut || "auto") : "auto"
      if (shortcut === "cmd")  return e.metaKey
      if (shortcut === "ctrl") return e.ctrlKey
      if (shortcut === "alt")  return e.altKey
      // auto: on Mac accept both Cmd+K and Ctrl+K so either key works
      return this._isMac ? (e.metaKey || e.ctrlKey) : e.ctrlKey
    }

    this.handleEvent("palette:sessions-result", ({ sessions }) => {
      if (this._paletteSessionsResolve) {
        this._paletteSessionsResolve(sessions)
        this._paletteSessionsResolve = null
      }
    })

    this.handleEvent("palette:recent-sessions-result", ({ sessions }) => {
      if (this._paletteRecentSessionsResolve) {
        this._paletteRecentSessionsResolve(sessions)
        this._paletteRecentSessionsResolve = null
      }
    })

    this.handleEvent("palette:list-agents-result", ({ agents }) => {
      if (this._paletteAgentsResolve) {
        this._paletteAgentsResolve(agents)
        this._paletteAgentsResolve = null
      }
    })

    this.handleEvent("palette:tasks-result", ({ tasks }) => {
      if (this._paletteTasksResolve) {
        this._paletteTasksResolve(tasks)
        this._paletteTasksResolve = null
      }
    })

    this._globalKeyHandler = (e) => {
      if (this._matchesModifier(e) && e.key.toLowerCase() === "k") {
        const inEditor = document.activeElement?.closest(".cm-editor, .monaco-editor, [data-palette-no-intercept]")
        if (inEditor) return
        e.preventDefault()
        this.open()
      }
    }
    window.addEventListener("keydown", this._globalKeyHandler)

    this._openHandler = () => this.open()
    this.el.addEventListener("palette:open", this._openHandler)

    this._openCommandHandler = (e) => this.openCommand(e.detail?.commandId)
    this.el.addEventListener("palette:open-command", this._openCommandHandler)

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
    this.el.removeEventListener("palette:open-command", this._openCommandHandler)
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

  async openCommand(commandId) {
    if (!commandId) return this.open()
    this.open()
    const cmd = getCommands(this).find(c => c.id === commandId && (!c.when || c.when()))
    if (cmd) await this.activate(cmd)
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
    const groupOrder = ["Current Project", "Workspace", "Projects", "Tasks", "Insights", "Knowledge", "Communication", "System"]
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
        return `<section class="px-1 py-1"><h3 class="px-2 py-1 text-xs uppercase tracking-wider text-base-content/40">${escapeHtml(group)}</h3><div>${buttons}</div></section>`
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
      ? item.shortcut.split(" ").map(k => `<kbd class="text-xs px-1 py-0.5 rounded border border-base-content/20 text-base-content/50">${escapeHtml(k)}</kbd>`).join(" ")
      : ""

    const chevronHtml = item.type === "submenu"
      ? `<span class="hero-chevron-right size-3 text-base-content/40 shrink-0"></span>`
      : ""

    const rightHtml = (shortcutHtml || chevronHtml)
      ? `<div class="flex items-center gap-1 ml-2 shrink-0">${shortcutHtml}${chevronHtml}</div>`
      : ""

    return `<button type="button" data-index="${idx}" role="option" aria-selected="${isActive}" class="w-full text-left rounded-lg px-3 py-2 text-sm flex items-center gap-2 transition-colors ${isActive ? "bg-base-content/8 text-base-content" : "hover:bg-base-content/5 text-base-content/80"}"><span class="${escapeHtml(item.icon)} size-4 shrink-0 text-base-content/50"></span><div class="flex-1 min-w-0"><div class="font-medium truncate">${labelHtml}</div>${hintHtml}</div>${rightHtml}</button>`
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

  updateActiveClass(prevIndex, nextIndex) {
    const prevBtn = this.results?.querySelector(`button[data-index="${prevIndex}"]`)
    const nextBtn = this.results?.querySelector(`button[data-index="${nextIndex}"]`)
    if (prevBtn) {
      prevBtn.classList.remove("bg-base-content/8", "text-base-content")
      prevBtn.classList.add("hover:bg-base-content/5", "text-base-content/80")
      prevBtn.setAttribute("aria-selected", "false")
    }
    if (nextBtn) {
      nextBtn.classList.remove("hover:bg-base-content/5", "text-base-content/80")
      nextBtn.classList.add("bg-base-content/8", "text-base-content")
      nextBtn.setAttribute("aria-selected", "true")
      nextBtn.scrollIntoView({ block: "nearest" })
    }
  },

  onInputKeydown(e) {
    const items = this.visibleItems || []
    const len = Math.max(items.length, 1)

    if (e.key === "ArrowDown") {
      e.preventDefault()
      const prevIndex = this.activeIndex
      this.activeIndex = (this.activeIndex + 1) % len
      this.updateActiveClass(prevIndex, this.activeIndex)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      const prevIndex = this.activeIndex
      this.activeIndex = (this.activeIndex - 1 + len) % len
      this.updateActiveClass(prevIndex, this.activeIndex)
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

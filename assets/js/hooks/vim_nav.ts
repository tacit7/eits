// assets/js/hooks/vim_nav.ts
import { COMMANDS, PREFIXES, type Command } from "./vim_nav_commands"

const EDITABLE_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"])

export function isEditableTarget(el: Element | EventTarget | null): boolean {
  if (!el || !(el instanceof HTMLElement)) return false
  if (EDITABLE_TAGS.has(el.tagName)) return true
  if (el.isContentEditable || el.getAttribute("contenteditable") === "true") return true
  if (el.getAttribute("role") === "textbox") return true
  return false
}

export function keyFromEvent(event: KeyboardEvent): string {
  if (event.key === " ") return "Space"
  return event.key.length === 1 ? event.key.toLowerCase() : event.key
}

function isFlyoutOpen(): boolean {
  return document.querySelector("[data-vim-flyout-open='true']") !== null
}

export function isCommandActive(cmd: Command): boolean {
  if (!cmd.scope || cmd.scope === "global") return true
  if (cmd.scope === "feature:vim-list") return !!document.querySelector("[data-vim-list]")
  if (cmd.scope === "feature:vim-flyout") return isFlyoutOpen()
  if (cmd.scope === "feature:vim-search") return !!document.querySelector("[data-vim-search]")
  if (cmd.scope === "page:sessions") return !!document.querySelector("[data-vim-page='sessions']")
  if (cmd.scope.startsWith("route_suffix:")) {
    const suffix = cmd.scope.slice("route_suffix:".length)
    const path = window.location.pathname
    return path.endsWith(suffix) || path.includes(suffix + "/")
  }
  return true
}

export function matchesKnownBindingOrPrefix(buffer: string[], key: string): boolean {
  const sequence = [...buffer, key]
  return COMMANDS.some(cmd => {
    if (!isCommandActive(cmd)) return false
    for (let i = 0; i < sequence.length; i++) {
      if (cmd.keys[i] !== sequence[i]) return false
    }
    return true
  })
}

// Re-export Command type for use in Task 3 hook implementation
export type { Command }

type Mode = "normal" | "insert"

// LiveView injects `el` and `pushEvent` at mount — Phoenix ships no official TS types,
// so we define the interface here for type safety.
interface LiveViewHook {
  el: HTMLElement
  pushEvent(event: string, payload: object, callback?: (reply: unknown) => void): void
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function createStatusbar(): HTMLElement {
  const el = document.createElement("div")
  el.id = "vim-nav-statusbar"
  el.setAttribute("aria-hidden", "true")
  el.style.cssText = [
    "position:fixed",
    "bottom:12px",
    "right:16px",
    "z-index:9999",
    "font-family:monospace",
    "font-size:11px",
    "padding:2px 6px",
    "border-radius:3px",
    "pointer-events:none",
    "background:transparent",
  ].join(";")
  return el
}

function updateStatusbar(el: HTMLElement, mode: Mode): void {
  if (mode === "normal") {
    el.textContent = "[ NORMAL ]"
    el.style.color = "var(--color-base-content)"
    el.style.opacity = "0.55"
  } else {
    el.textContent = "[ INSERT ]"
    el.style.color = "var(--color-info, var(--color-primary))"
    el.style.opacity = "0.9"
  }
}

export const VimNav = {
  // Injected by LiveView at runtime — `null as unknown as` is intentional since
  // Phoenix provides no official TS types for hook lifecycle properties.
  el: null as unknown as LiveViewHook["el"],
  pushEvent: null as unknown as LiveViewHook["pushEvent"],
  pushEventToShell: null as ((event: string, payload: object) => void) | null,
  pushToList: null as ((event: string, payload: object) => void) | null,
  flyoutFocused: false as boolean,
  mode: "normal" as Mode,
  buffer: [] as string[],
  sequenceTimer: null as ReturnType<typeof setTimeout> | null,
  statusbarEl: null as HTMLElement | null,
  helpOverlayEl: null as HTMLElement | null,
  whichKeyEl: null as HTMLElement | null,
  whichKeyTimer: null as ReturnType<typeof setTimeout> | null,
  _onKeydown: null as ((e: KeyboardEvent) => void) | null,
  _onFocusin: null as ((e: FocusEvent) => void) | null,
  _onFocusout: null as ((e: FocusEvent) => void) | null,
  _onHelpClose: null as ((e: KeyboardEvent) => void) | null,
  _onWhichKeyClose: null as ((e: KeyboardEvent) => void) | null,
  _onPageLoad: null as ((e: Event) => void) | null,
  listFocusIndex: -1 as number,

  mounted() {
    if (!this.isEnabled()) return
    this.mode = isEditableTarget(document.activeElement) ? "insert" : "normal"
    this.statusbarEl = createStatusbar()
    updateStatusbar(this.statusbarEl, this.mode)
    document.body.appendChild(this.statusbarEl)

    this._onKeydown = (e: KeyboardEvent) => this.handleKey(e)
    this._onFocusin = (e: FocusEvent) => {
      if (isEditableTarget(e.target)) this.setMode("insert")
    }
    this._onFocusout = (e: FocusEvent) => {
      if (isEditableTarget(e.target)) {
        setTimeout(() => {
          if (!isEditableTarget(document.activeElement)) this.setMode("normal")
        }, 0)
      }
    }

    this._onPageLoad = () => this.clearListFocus()
    window.addEventListener("phx:page-loading-stop", this._onPageLoad)

    document.addEventListener("keydown", this._onKeydown, { capture: true })
    document.addEventListener("focusin", this._onFocusin)
    document.addEventListener("focusout", this._onFocusout)
  },

  destroyed() {
    if (this._onKeydown) document.removeEventListener("keydown", this._onKeydown, { capture: true } as EventListenerOptions)
    if (this._onFocusin) document.removeEventListener("focusin", this._onFocusin)
    if (this._onFocusout) document.removeEventListener("focusout", this._onFocusout)
    if (this._onPageLoad) window.removeEventListener("phx:page-loading-stop", this._onPageLoad)
    if (this.sequenceTimer) clearTimeout(this.sequenceTimer)
    this.hideHelp()
    this.hideWhichKey()
    this.clearListFocus()
    this.statusbarEl?.remove()
    this.statusbarEl = null
    this._onKeydown = null
    this._onFocusin = null
    this._onFocusout = null
    this._onPageLoad = null
  },

  isEnabled(): boolean {
    return (this.el as HTMLElement).dataset.vimNavEnabled === "true"
  },

  setMode(mode: Mode) {
    this.mode = mode
    if (this.statusbarEl) updateStatusbar(this.statusbarEl, mode)
  },

  handleKey(event: KeyboardEvent) {
    if (!this.isEnabled()) return
    if (event.defaultPrevented) return
    if (event.isComposing) return

    // Phase 1: insert mode — only Esc exits
    if (this.mode === "insert") {
      if (event.key === "Escape" && isEditableTarget(event.target)) {
        // Don't preventDefault — lets browser close any open <dialog> naturally
        ;(event.target as HTMLElement).blur()
        this.setMode("normal")
      }
      return
    }

    // Phase 2: normal mode
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (isEditableTarget(event.target)) return

    const key = keyFromEvent(event)

    if (key === "Escape") {
      if (this.flyoutFocused) {
        this.clearListFocus()
        return
      }
      this.clearSequence()
      this.hideHelp()
      this.pushEventToShell?.("close_proj_picker", {})
      return
    }

    if (!matchesKnownBindingOrPrefix(this.buffer, key)) return

    event.preventDefault()
    this.buffer.push(key)
    if (this.buffer.length === 1 && PREFIXES.has(key)) {
      this.showWhichKey(key)
    } else {
      this.hideWhichKey()
    }
    this.resetSequenceTimer()

    const cmd = COMMANDS.find(c =>
      c.keys.length === this.buffer.length &&
      c.keys.every((k, i) => k === this.buffer[i])
    )

    if (cmd) {
      this.clearSequence()
      this.executeCommand(cmd)
    }
  },

  clearSequence() {
    this.buffer = []
    if (this.sequenceTimer) { clearTimeout(this.sequenceTimer); this.sequenceTimer = null }
    this.hideWhichKey()
  },

  resetSequenceTimer() {
    if (this.sequenceTimer) clearTimeout(this.sequenceTimer)
    this.sequenceTimer = setTimeout(() => this.clearSequence(), 1000)
  },

  currentProjectPath(): string | null {
    const m = window.location.pathname.match(/^(\/projects\/\d+)/)
    if (m) return m[1]
    const railId = (document.getElementById("app-rail") as HTMLElement | null)?.dataset.projectId
    return railId ? `/projects/${railId}` : null
  },

  buildPath(path: string, relative?: boolean): string | null {
    if (!relative) return path
    const projectPath = this.currentProjectPath()
    if (!projectPath) return null
    const segment = path.replace(/^\//, "")
    return `${projectPath}/${segment}`
  },

  currentList(): HTMLElement | null {
    return document.querySelector("[data-vim-list]")
  },

  currentListItems(): HTMLElement[] {
    if (this.flyoutFocused) {
      return [...document.querySelectorAll<HTMLElement>("[data-vim-flyout-item]")]
    }
    const list = this.currentList()
    if (!list) return []
    return [...list.querySelectorAll<HTMLElement>("[data-vim-list-item]")]
  },

  focusListItem(index: number): void {
    const items = this.currentListItems()
    if (items.length === 0) return
    items.forEach(el => el.classList.remove("vim-nav-focused"))
    const item = items[index]
    if (item) {
      item.classList.add("vim-nav-focused")
      item.scrollIntoView?.({ block: "nearest" })
      this.listFocusIndex = index
    }
  },

  clearListFocus(): void {
    document.querySelectorAll<HTMLElement>("[data-vim-list-item], [data-vim-flyout-item]")
      .forEach(el => el.classList.remove("vim-nav-focused"))
    this.listFocusIndex = -1
    this.flyoutFocused = false
  },

  executeCommand(cmd: Command) {
    const { action } = cmd
    if (action.kind === "navigate") {
      const target = this.buildPath(action.path, action.relative)
      if (target) window.location.href = target
      return
    }
    if (action.kind === "push_event") {
      const fn = action.target === "shell" ? this.pushEventToShell : this.pushEvent
      if (typeof fn === "function") fn(action.event, action.payload ?? {})
      return
    }
    if (action.kind === "client") {
      if (action.name === "help") { this.showHelp(); return }
      if (action.name === "history_back") { history.back(); return }
      if (action.name === "history_forward") { history.forward(); return }
      if (action.name === "command_palette") {
        document.getElementById("command-palette")?.dispatchEvent(new CustomEvent("palette:open"))
        return
      }
      if (action.name === "quick_create_note") {
        window.dispatchEvent(new Event("palette:create-note"))
        return
      }
      if (action.name === "quick_create_task") {
        window.dispatchEvent(new Event("palette:create-task"))
        return
      }
      if (action.name === "quick_create_chat") {
        window.dispatchEvent(new Event("palette:create-chat"))
        return
      }
      if (action.name === "list_next") {
        const items = this.currentListItems()
        if (items.length === 0) return
        const next = Math.min(this.listFocusIndex + 1, items.length - 1)
        this.focusListItem(next)
        return
      }
      if (action.name === "list_prev") {
        const items = this.currentListItems()
        if (items.length === 0) return
        const prev = Math.max(this.listFocusIndex - 1, 0)
        this.focusListItem(prev)
        return
      }
      if (action.name === "list_open") {
        const item = this.currentListItems()[this.listFocusIndex]
        item?.click()
        return
      }
      if (action.name === "page_search") {
        const input = document.querySelector("[data-vim-search]") as HTMLInputElement | null
        input?.focus()
        return
      }
      if (action.name === "list_archive" || action.name === "list_delete") {
        const item = this.currentListItems()[this.listFocusIndex]
        if (!item) return
        const sessionId = item.dataset.sessionId
        if (!sessionId) return
        const event = action.name === "list_archive" ? "archive_session" : "delete_session"
        this.pushToList?.(event, { session_id: sessionId })
        return
      }
      if (action.name === "list_yank_uuid" || action.name === "list_yank_id") {
        const item = this.currentListItems()[this.listFocusIndex]
        if (!item) return
        const value = action.name === "list_yank_uuid" ? item.dataset.sessionUuid : item.dataset.sessionId
        if (!value) return
        navigator.clipboard.writeText(value).catch(() => {})
        return
      }
      if (action.name === "focus_flyout") {
        const items = [...document.querySelectorAll<HTMLElement>("[data-vim-flyout-item]")]
        if (items.length === 0) return
        this.flyoutFocused = true
        this.listFocusIndex = 0
        this.focusListItem(0)
        return
      }
      if (action.name === "focus_composer") {
        const composer = document.querySelector<HTMLElement>("[data-vim-composer]")
        composer?.focus()
        return
      }
    }
  },

  showHelp() {
    if (this.helpOverlayEl) { this.hideHelp(); return }

    const overlay = document.createElement("div")
    overlay.id = "vim-nav-help"
    overlay.setAttribute("aria-label", "Keyboard shortcuts")
    overlay.style.cssText = [
      "position:fixed","inset:0","z-index:10000",
      "display:flex","align-items:center","justify-content:center",
      "background:rgba(0,0,0,0.6)",
    ].join(";")

    const groups: Record<string, Command[]> = {}
    for (const cmd of COMMANDS) {
      if (!isCommandActive(cmd)) continue
      if (!groups[cmd.group]) groups[cmd.group] = []
      groups[cmd.group].push(cmd)
    }

    const groupLabels: Record<string, string> = {
      navigation: "Go to", toggle: "Toggle", create: "New",
      global: "Global", context: "Context",
    }

    let html = `<div style="background:var(--color-base-100);border:1px solid var(--color-base-300);border-radius:8px;padding:24px;min-width:360px;max-width:520px;font-family:monospace;color:var(--color-base-content)">
      <div style="font-size:14px;font-weight:600;margin-bottom:16px">Keyboard Shortcuts</div>`

    for (const [group, cmds] of Object.entries(groups)) {
      html += `<div style="margin-bottom:12px">
        <div style="font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:var(--color-base-content);opacity:.6;margin-bottom:6px">${escapeHtml(groupLabels[group] ?? group)}</div>`
      for (const cmd of cmds) {
        const keys = cmd.keys.map(k =>
          `<kbd style="display:inline-block;padding:1px 5px;border:1px solid var(--color-base-300);border-radius:3px;font-size:11px;background:var(--color-base-200);color:var(--color-base-content)">${escapeHtml(k)}</kbd>`
        ).join(" ")
        html += `<div style="display:flex;justify-content:space-between;align-items:center;padding:3px 0">
          <span style="font-size:12px;color:var(--color-base-content);opacity:.8">${escapeHtml(cmd.label)}</span>
          <span>${keys}</span></div>`
      }
      html += `</div>`
    }

    html += `<div style="margin-top:12px;font-size:10px;color:var(--color-base-content);opacity:.5;text-align:center">Press any key to close</div></div>`
    overlay.innerHTML = html

    this._onHelpClose = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (["Shift", "Control", "Meta", "Alt"].includes(e.key)) return
      e.preventDefault()
      this.hideHelp()
    }
    document.addEventListener("keydown", this._onHelpClose, { capture: true })
    document.body.appendChild(overlay)
    this.helpOverlayEl = overlay
  },

  hideHelp() {
    if (this._onHelpClose) {
      document.removeEventListener("keydown", this._onHelpClose, { capture: true } as EventListenerOptions)
      this._onHelpClose = null
    }
    this.helpOverlayEl?.remove()
    this.helpOverlayEl = null
  },

  showWhichKey(prefix: string) {
    if (this.whichKeyTimer) clearTimeout(this.whichKeyTimer)
    this.whichKeyTimer = setTimeout(() => this._renderWhichKey(prefix), 300)
  },

  _renderWhichKey(prefix: string) {
    this.whichKeyTimer = null
    // Cancel the sequence auto-dismiss — overlay stays until user acts
    if (this.sequenceTimer) { clearTimeout(this.sequenceTimer); this.sequenceTimer = null }
    // Remove any existing which-key overlay
    this.whichKeyEl?.remove()
    this.whichKeyEl = null

    const prefixCmds = COMMANDS.filter(cmd => cmd.keys.length > 1 && cmd.keys[0] === prefix && isCommandActive(cmd))
    if (prefixCmds.length === 0) return

    const overlay = document.createElement("div")
    overlay.id = "vim-nav-which-key"
    overlay.setAttribute("aria-hidden", "true")
    overlay.style.cssText = [
      "position:fixed",
      "bottom:48px",
      "left:50%",
      "transform:translateX(-50%)",
      "z-index:9999",
      "font-family:monospace",
      "font-size:12px",
      "background:var(--color-base-200)",
      "border:1px solid var(--color-base-300)",
      "border-radius:6px",
      "padding:8px 12px",
      "display:flex",
      "flex-direction:column",
      "gap:4px",
      "pointer-events:none",
      "color:var(--color-base-content)",
      "min-width:200px",
    ].join(";")

    const header = document.createElement("div")
    header.style.cssText = "font-size:10px;color:var(--color-base-content);opacity:.6;margin-bottom:4px;text-transform:uppercase;letter-spacing:.08em"
    header.textContent = `${prefix} →`
    overlay.appendChild(header)

    for (const cmd of prefixCmds) {
      const row = document.createElement("div")
      row.style.cssText = "display:flex;align-items:center;gap:8px"
      const key = cmd.keys[1] ?? ""
      row.innerHTML = `<kbd style="display:inline-block;padding:1px 5px;border:1px solid var(--color-base-300);border-radius:3px;font-size:11px;background:var(--color-base-100);color:var(--color-base-content);min-width:18px;text-align:center">${escapeHtml(key)}</kbd><span style="color:var(--color-base-content);opacity:.8">${escapeHtml(cmd.label)}</span>`
      overlay.appendChild(row)
    }

    this._onWhichKeyClose = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (["Shift", "Control", "Meta", "Alt"].includes(e.key)) return
      // Don't preventDefault — let the key continue to handleKey
      this.hideWhichKey()
    }
    document.addEventListener("keydown", this._onWhichKeyClose, { capture: true })
    document.body.appendChild(overlay)
    this.whichKeyEl = overlay
  },

  hideWhichKey() {
    if (this.whichKeyTimer) { clearTimeout(this.whichKeyTimer); this.whichKeyTimer = null }
    if (this._onWhichKeyClose) {
      document.removeEventListener("keydown", this._onWhichKeyClose, { capture: true } as EventListenerOptions)
      this._onWhichKeyClose = null
    }
    this.whichKeyEl?.remove()
    this.whichKeyEl = null
  },
}

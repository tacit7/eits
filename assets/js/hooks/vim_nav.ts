// assets/js/hooks/vim_nav.ts
import { COMMANDS, type Command } from "./vim_nav_commands"

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

export function matchesKnownBindingOrPrefix(buffer: string[], key: string): boolean {
  const sequence = [...buffer, key]
  return COMMANDS.some(cmd => {
    for (let i = 0; i < sequence.length; i++) {
      if (cmd.keys[i] !== sequence[i]) return false
    }
    return true
  })
}

// Re-export Command type for use in Task 3 hook implementation
export type { Command }

type Mode = "normal" | "insert"

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
    el.style.color = "rgba(156,163,175,0.6)"
  } else {
    el.textContent = "[ INSERT ]"
    el.style.color = "rgba(96,165,250,0.85)"
  }
}

export const VimNav = {
  el: null as unknown as HTMLElement,
  pushEvent: null as unknown as (event: string, payload: object) => void,
  mode: "normal" as Mode,
  buffer: [] as string[],
  prefixTimer: null as ReturnType<typeof setTimeout> | null,
  sequenceTimer: null as ReturnType<typeof setTimeout> | null,
  statusbarEl: null as HTMLElement | null,
  helpOverlayEl: null as HTMLElement | null,
  _onKeydown: null as ((e: KeyboardEvent) => void) | null,
  _onFocusin: null as ((e: FocusEvent) => void) | null,
  _onFocusout: null as ((e: FocusEvent) => void) | null,

  mounted() {
    if (!this.isEnabled()) return
    this.mode = isEditableTarget(document.activeElement) ? "insert" : "normal"
    this.statusbarEl = createStatusbar()
    updateStatusbar(this.statusbarEl, this.mode)
    document.body.appendChild(this.statusbarEl)

    this._onKeydown = (e: KeyboardEvent) => this.handleKey(e)
    this._onFocusin = () => this.setMode("insert")
    this._onFocusout = (e: FocusEvent) => {
      if (isEditableTarget(e.target)) {
        setTimeout(() => {
          if (!isEditableTarget(document.activeElement)) this.setMode("normal")
        }, 0)
      }
    }

    document.addEventListener("keydown", this._onKeydown, { capture: true })
    document.addEventListener("focusin", this._onFocusin)
    document.addEventListener("focusout", this._onFocusout)
  },

  destroyed() {
    if (this._onKeydown) document.removeEventListener("keydown", this._onKeydown, { capture: true } as EventListenerOptions)
    if (this._onFocusin) document.removeEventListener("focusin", this._onFocusin)
    if (this._onFocusout) document.removeEventListener("focusout", this._onFocusout)
    if (this.prefixTimer) clearTimeout(this.prefixTimer)
    if (this.sequenceTimer) clearTimeout(this.sequenceTimer)
    this.statusbarEl?.remove()
    this.helpOverlayEl?.remove()
    this.statusbarEl = null
    this.helpOverlayEl = null
    this._onKeydown = null
    this._onFocusin = null
    this._onFocusout = null
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
        event.preventDefault()
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
      this.clearSequence()
      this.hideHelp()
      return
    }

    if (!matchesKnownBindingOrPrefix(this.buffer, key)) return

    event.preventDefault()
    this.buffer.push(key)
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
    if (this.prefixTimer) { clearTimeout(this.prefixTimer); this.prefixTimer = null }
    if (this.sequenceTimer) { clearTimeout(this.sequenceTimer); this.sequenceTimer = null }
  },

  resetSequenceTimer() {
    if (this.sequenceTimer) clearTimeout(this.sequenceTimer)
    this.sequenceTimer = setTimeout(() => this.clearSequence(), 1000)
  },

  buildPath(path: string, relative?: boolean): string {
    if (!relative) return path
    const projectPath = (this.el as HTMLElement).dataset.vimProjectPath
    if (projectPath) return `${projectPath}/${path}`
    return `/workspace/${path}`
  },

  executeCommand(cmd: Command) {
    const { action } = cmd
    if (action.kind === "navigate") {
      window.location.href = this.buildPath(action.path, action.relative)
      return
    }
    if (action.kind === "push_event") {
      this.pushEvent(action.event, action.payload ?? {})
      return
    }
    if (action.kind === "client") {
      if (action.name === "help") { this.showHelp(); return }
      if (action.name === "history_back") { history.back(); return }
      if (action.name === "history_forward") { history.forward(); return }
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
      if (!groups[cmd.group]) groups[cmd.group] = []
      groups[cmd.group].push(cmd)
    }

    const groupLabels: Record<string, string> = {
      navigation: "Go to", toggle: "Toggle", create: "New",
      global: "Global", context: "Context",
    }

    let html = `<div style="background:var(--b1,#1a1a2e);border:1px solid var(--b3,#374151);border-radius:8px;padding:24px;min-width:360px;max-width:520px;font-family:monospace;color:var(--bc,#e5e7eb)">
      <div style="font-size:14px;font-weight:600;margin-bottom:16px">Keyboard Shortcuts</div>`

    for (const [group, cmds] of Object.entries(groups)) {
      html += `<div style="margin-bottom:12px">
        <div style="font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:rgba(156,163,175,.6);margin-bottom:6px">${groupLabels[group] ?? group}</div>`
      for (const cmd of cmds) {
        const keys = cmd.keys.map(k =>
          `<kbd style="display:inline-block;padding:1px 5px;border:1px solid rgba(156,163,175,.4);border-radius:3px;font-size:11px;background:rgba(255,255,255,.05)">${k}</kbd>`
        ).join(" ")
        html += `<div style="display:flex;justify-content:space-between;align-items:center;padding:3px 0">
          <span style="font-size:12px;color:rgba(229,231,235,.8)">${cmd.label}</span>
          <span>${keys}</span></div>`
      }
      html += `</div>`
    }

    html += `<div style="margin-top:12px;font-size:10px;color:rgba(156,163,175,.5);text-align:center">Press any key to close</div></div>`
    overlay.innerHTML = html

    const close = (e: KeyboardEvent) => {
      e.preventDefault()
      this.hideHelp()
      document.removeEventListener("keydown", close, { capture: true } as EventListenerOptions)
    }
    document.addEventListener("keydown", close, { capture: true })
    document.body.appendChild(overlay)
    this.helpOverlayEl = overlay
  },

  hideHelp() {
    this.helpOverlayEl?.remove()
    this.helpOverlayEl = null
  },
}

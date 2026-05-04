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
  return event.key
}

function isFlyoutOpen(): boolean {
  return document.querySelector("[data-vim-flyout-open='true']") !== null
}

export function isCommandActive(cmd: Command): boolean {
  if (!cmd.scope || cmd.scope === "global") return true
  // j/k/Enter (feature:vim-list) must also work when flyout is open so navigation
  // is reachable on pages without a main list. Whether they target main list or
  // flyout items is decided by VimNav.flyoutFocused at execute time.
  if (cmd.scope === "feature:vim-list") return !!document.querySelector("[data-vim-list]") || isFlyoutOpen()
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

function updateStatusbar(el: HTMLElement, mode: Mode, count = 0): void {
  if (mode === "normal") {
    el.textContent = count > 0 ? `[ NORMAL ] ${count}` : "[ NORMAL ]"
    el.style.color = "var(--color-base-content)"
    el.style.opacity = "0.55"
  } else {
    el.textContent = "[ INSERT ]"
    el.style.color = "var(--color-info, var(--color-primary))"
    el.style.opacity = "0.9"
  }
}

function _generateHintLabels(count: number): string[] {
  const alpha = "abcdefghijklmnopqrstuvwxyz"
  const labels: string[] = []
  for (let i = 0; labels.length < count && i < alpha.length; i++) {
    labels.push(alpha[i])
  }
  for (let i = 0; labels.length < count && i < alpha.length; i++) {
    for (let j = 0; labels.length < count && j < alpha.length; j++) {
      labels.push(alpha[i] + alpha[j])
    }
  }
  return labels
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
  _onPageLoad: null as ((e: Event) => void) | null,
  listFocusIndex: -1 as number,
  count: 0 as number,
  countTimer: null as ReturnType<typeof setTimeout> | null,
  hintMode: false as boolean,
  hintBuffer: "" as string,
  hintLabels: [] as Array<{ label: string; index: number }>,
  hintOverlayEl: null as HTMLElement | null,

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

    this._onPageLoad = () => {
      this.clearListFocus()
      this._recordSessionVisit()
    }
    window.addEventListener("phx:page-loading-stop", this._onPageLoad)

    document.addEventListener("keydown", this._onKeydown, { capture: true })
    document.addEventListener("focusin", this._onFocusin)
    document.addEventListener("focusout", this._onFocusout)

    this.handleEvent("vim:session-nav-result", ({ url }: { url: string | null }) => {
      if (url) window.location.href = url
    })
    this.handleEvent("vim:task-nav-result", ({ url }: { url: string | null }) => {
      if (url) window.location.assign(url)
    })
  },

  destroyed() {
    if (this._onKeydown) document.removeEventListener("keydown", this._onKeydown, { capture: true } as EventListenerOptions)
    if (this._onFocusin) document.removeEventListener("focusin", this._onFocusin)
    if (this._onFocusout) document.removeEventListener("focusout", this._onFocusout)
    if (this._onPageLoad) window.removeEventListener("phx:page-loading-stop", this._onPageLoad)
    if (this.sequenceTimer) clearTimeout(this.sequenceTimer)
    if (this.countTimer) clearTimeout(this.countTimer)
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
    if (this.statusbarEl) updateStatusbar(this.statusbarEl, mode, this.count)
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
    // Hint mode: intercept all keystrokes while active.
    if (this.hintMode) {
      event.preventDefault()
      if (event.key === "Escape") {
        this.exitHintMode()
      } else if (/^[a-z]$/i.test(event.key) && !event.ctrlKey && !event.metaKey && !event.altKey) {
        this.hintBuffer += event.key.toLowerCase()
        this._updateHintFilter()
      }
      return
    }

    // Ctrl-D / Ctrl-U: half-page scroll; Ctrl-N / Ctrl-P: single-step j/k aliases.
    // All handled before the modifier guard so they work regardless of other ctrl bindings.
    if (event.ctrlKey && !event.metaKey && !event.altKey && !isEditableTarget(event.target)) {
      const key = event.key.toLowerCase()
      if ((key === "d" || key === "u") && (document.querySelector("[data-vim-list]") || isFlyoutOpen())) {
        event.preventDefault()
        const items = this.currentListItems()
        if (items.length > 0) {
          const listEl = this.currentList()
          const containerHeight = listEl ? listEl.clientHeight : window.innerHeight
          const itemHeight = items[0].offsetHeight || 48
          const halfPage = Math.max(1, Math.floor(containerHeight / itemHeight / 2))
          const startIndex = this.listFocusIndex < 0 ? 0 : this.listFocusIndex
          if (key === "d") {
            this.focusListItem(Math.min(startIndex + halfPage, items.length - 1))
          } else {
            this.focusListItem(Math.max(startIndex - halfPage, 0))
          }
        }
        return
      }
      if ((key === "n" || key === "p") && (document.querySelector("[data-vim-list]") || isFlyoutOpen())) {
        event.preventDefault()
        const items = this.currentListItems()
        if (items.length > 0) {
          const cur = this.listFocusIndex < 0 ? 0 : this.listFocusIndex
          if (key === "n") {
            this.focusListItem(Math.min(cur + 1, items.length - 1))
          } else {
            this.focusListItem(Math.max(cur - 1, 0))
          }
        }
        return
      }
    }

    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (isEditableTarget(event.target)) return

    const key = keyFromEvent(event)

    // Numeric count prefix: accumulate digits when buffer is empty
    if (/^[0-9]$/.test(key) && this.buffer.length === 0) {
      this.count = this.count * 10 + parseInt(key, 10)
      if (this.countTimer) clearTimeout(this.countTimer)
      this.countTimer = setTimeout(() => {
        this.count = 0
        if (this.statusbarEl) updateStatusbar(this.statusbarEl, this.mode, 0)
        this.countTimer = null
      }, 2000)
      if (this.statusbarEl) updateStatusbar(this.statusbarEl, this.mode, this.count)
      event.preventDefault()
      return
    }

    if (key === "Escape") {
      this.count = 0
      if (this.countTimer) { clearTimeout(this.countTimer); this.countTimer = null }
      if (this.statusbarEl) updateStatusbar(this.statusbarEl, this.mode, 0)
      if (this.flyoutFocused) {
        this.clearListFocus()
        return
      }
      this.clearSequence()
      this.hideHelp()
      this.pushEventToShell?.("close_proj_picker", {})
      return
    }

    // ? with an active buffer shows scoped help for the current prefix
    if (key === "?" && this.buffer.length > 0) {
      event.preventDefault()
      this.showHelp([...this.buffer])
      this.clearSequence()
      return
    }

    if (!matchesKnownBindingOrPrefix(this.buffer, key)) {
      if (this.whichKeyEl) this.hideWhichKey()
      return
    }

    event.preventDefault()
    this.buffer.push(key)

    // Show which-key when current buffer is a prefix of at least one deeper active command.
    // Space sequences get 0ms delay (immediate) and a longer sequence window.
    const isLeader = this.buffer[0] === "Space"
    const hasDeeper = COMMANDS.some(c =>
      c.keys.length > this.buffer.length &&
      this.buffer.every((k, i) => c.keys[i] === k) &&
      isCommandActive(c)
    )
    if (hasDeeper) {
      this.showWhichKey([...this.buffer], isLeader ? 500 : 300)
    } else {
      this.hideWhichKey()
    }
    this.resetSequenceTimer()

    const cmd = COMMANDS.find(c =>
      isCommandActive(c) &&
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
    const timeout = this.buffer[0] === "Space" ? 2000 : 1000
    this.sequenceTimer = setTimeout(() => this.clearSequence(), timeout)
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
    // Defensive: if flyout was closed via non-vim path (mouse, route change),
    // drop stale focus state so j/k revert to the page list.
    if (this.flyoutFocused && !isFlyoutOpen()) {
      this.flyoutFocused = false
      this.listFocusIndex = -1
    }
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
    if (this.hintMode) this.exitHintMode()
  },

  _focusFlyoutAfterOpen(): void {
    const tryFocus = (): boolean => {
      if (!isFlyoutOpen()) return false
      const items = [...document.querySelectorAll<HTMLElement>("[data-vim-flyout-item]")]
      if (items.length === 0) return false
      this.flyoutFocused = true
      this.listFocusIndex = 0
      this.focusListItem(0)
      return true
    }
    if (tryFocus()) return
    const obs = new MutationObserver(() => { if (tryFocus()) obs.disconnect() })
    // Watch both attribute flips (closed→open) and childList (items inserted late
    // when flyout was already open). Either path needs to wake tryFocus.
    obs.observe(document.body, {
      subtree: true,
      attributes: true,
      attributeFilter: ["data-vim-flyout-open"],
      childList: true,
    })
    setTimeout(() => obs.disconnect(), 2000)
  },

  executeCommand(cmd: Command) {
    const times = this.count > 0 ? this.count : 1
    const rawCount = this.count
    this.count = 0
    if (this.countTimer) { clearTimeout(this.countTimer); this.countTimer = null }
    if (this.statusbarEl) updateStatusbar(this.statusbarEl, this.mode, 0)

    const { action } = cmd
    if (action.kind === "navigate") {
      const target = this.buildPath(action.path, action.relative)
      if (target) window.location.href = target
      return
    }
    if (action.kind === "push_event") {
      // Closing the flyout via q must also drop flyout-focus state, otherwise
      // j/k continue to target now-hidden flyout items instead of the page list.
      if (action.event === "close_flyout" && this.flyoutFocused) {
        this.clearListFocus()
      }
      const fn = action.target === "shell" ? this.pushEventToShell : this.pushEvent
      if (typeof fn === "function") fn(action.event, action.payload ?? {})
      if (action.focus_flyout_after) this._focusFlyoutAfterOpen()
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
        const next = Math.min(this.listFocusIndex + times, items.length - 1)
        this.focusListItem(next)
        return
      }
      if (action.name === "list_prev") {
        const items = this.currentListItems()
        if (items.length === 0) return
        const prev = Math.max(this.listFocusIndex - times, 0)
        this.focusListItem(prev)
        return
      }
      if (action.name === "list_top") {
        const items = this.currentListItems()
        if (items.length === 0) return
        this.focusListItem(0)
        return
      }
      if (action.name === "list_bottom") {
        const items = this.currentListItems()
        if (items.length === 0) return
        if (rawCount > 0 && rawCount <= items.length) {
          this.focusListItem(rawCount - 1)
        } else {
          this.focusListItem(items.length - 1)
        }
        return
      }
      if (action.name === "list_open") {
        const item = this.currentListItems()[this.listFocusIndex]
        item?.click()
        return
      }
      if (action.name === "list_open_tab") {
        const item = this.currentListItems()[this.listFocusIndex]
        if (!item) return
        const anchor = (item.tagName === "A" ? item : item.querySelector<HTMLAnchorElement>("a[href]")) as HTMLAnchorElement | null
        const href = anchor?.getAttribute("href")
        if (href) window.open(href, "_blank", "noopener,noreferrer")
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
        // Save the target index so we can refocus after LiveView removes the row.
        const savedIndex = this.listFocusIndex
        // Watch for the item's removal from the DOM (LiveView stream_delete fires
        // asynchronously after the server round-trip), then focus the item that
        // slides into the saved position, or the new last item if at the end.
        const obs = new MutationObserver(() => {
          if (item.isConnected) return
          obs.disconnect()
          const items = this.currentListItems()
          if (items.length === 0) {
            this.listFocusIndex = -1
            return
          }
          this.focusListItem(Math.min(savedIndex, items.length - 1))
        })
        obs.observe(document.body, { childList: true, subtree: true })
        // Safety: disconnect after 3 s in case the server never removes the item.
        setTimeout(() => obs.disconnect(), 3000)
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
      if (action.name === "list_yank_title") {
        const item = this.currentListItems()[this.listFocusIndex]
        if (!item) return
        const value = item.dataset.vimItemTitle
        if (!value) return
        navigator.clipboard.writeText(value).catch(() => {})
        return
      }
      if (action.name === "list_rename") {
        const item = this.currentListItems()[this.listFocusIndex]
        if (!item) return
        const selector = item.dataset.vimRenameTarget
        if (!selector) return
        const input = item.querySelector<HTMLElement>(selector)
        if (!input) return
        input.focus()
        if (input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement) {
          input.select()
        }
        this.setMode("insert")
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
      if (action.name === "find_sessions") {
        document.getElementById("command-palette")?.dispatchEvent(
          new CustomEvent("palette:open-command", { detail: { commandId: "list-sessions" } })
        )
        return
      }
      if (action.name === "find_recent_sessions") {
        document.getElementById("command-palette")?.dispatchEvent(
          new CustomEvent("palette:open-command", { detail: { commandId: "recent-sessions" } })
        )
        return
      }
      if (action.name === "find_tasks") {
        document.getElementById("command-palette")?.dispatchEvent(
          new CustomEvent("palette:open-command", { detail: { commandId: "list-tasks" } })
        )
        return
      }
      if (action.name === "find_notes") {
        document.getElementById("command-palette")?.dispatchEvent(
          new CustomEvent("palette:open-command", { detail: { commandId: "list-notes" } })
        )
        return
      }
      if (action.name === "find_projects") {
        document.getElementById("command-palette")?.dispatchEvent(
          new CustomEvent("palette:open-command", { detail: { commandId: "list-projects" } })
        )
        return
      }
      if (action.name === "hint_mode_enter") {
        this.enterHintMode()
        return
      }
      if (action.name === "session_nav_next" || action.name === "session_nav_prev") {
        const direction = action.name === "session_nav_next" ? "next" : "prev"
        this.pushEvent("vim:session-nav", { direction, current_path: window.location.pathname })
        return
      }
      if (action.name === "task_nav_next" || action.name === "task_nav_prev") {
        const direction = action.name === "task_nav_next" ? "next" : "prev"
        const taskUuidMatch = window.location.search.match(/[?&]task=([a-f0-9-]+)/)
        const task_uuid = taskUuidMatch ? taskUuidMatch[1] : null
        this.pushEvent("vim:task-nav", { direction, task_uuid, current_path: window.location.pathname })
        return
      }
      if (action.name === "list_group_prev" || action.name === "list_group_next") {
        const items = this.currentListItems()
        if (items.length === 0) return
        const separators = [...document.querySelectorAll<HTMLElement>("[data-vim-list-group]")]
        if (separators.length === 0) {
          // Fallback: no group separators — behave like gg / G
          if (action.name === "list_group_prev") this.focusListItem(0)
          else this.focusListItem(items.length - 1)
          return
        }
        const currentEl = items[this.listFocusIndex < 0 ? 0 : this.listFocusIndex]
        if (action.name === "list_group_next") {
          // Find the next separator after the current element, then focus the first
          // list item whose DOM position is after that separator.
          const nextSep = separators.find(sep =>
            currentEl.compareDocumentPosition(sep) & Node.DOCUMENT_POSITION_FOLLOWING
          )
          if (!nextSep) { this.focusListItem(items.length - 1); return }
          const firstAfter = items.find(item =>
            nextSep.compareDocumentPosition(item) & Node.DOCUMENT_POSITION_FOLLOWING
          )
          if (firstAfter) this.focusListItem(items.indexOf(firstAfter))
          else this.focusListItem(items.length - 1)
        } else {
          // list_group_prev: find the separator immediately before the current element,
          // then focus the first list item after the separator before that one (or item 0).
          const sepsBeforeCurrent = separators.filter(sep =>
            currentEl.compareDocumentPosition(sep) & Node.DOCUMENT_POSITION_PRECEDING
          )
          if (sepsBeforeCurrent.length === 0) { this.focusListItem(0); return }
          // The group containing the current item starts right after the last separator before it.
          const ownSep = sepsBeforeCurrent[sepsBeforeCurrent.length - 1]
          // If we're already at the first item of our group (nothing between ownSep and currentEl),
          // jump to the group before ownSep.
          const itemsBetween = items.filter(item =>
            (ownSep.compareDocumentPosition(item) & Node.DOCUMENT_POSITION_FOLLOWING) &&
            (item.compareDocumentPosition(currentEl) & Node.DOCUMENT_POSITION_FOLLOWING)
          )
          if (itemsBetween.length > 0) {
            // Not at group head — go to the first item of our own group
            this.focusListItem(items.indexOf(itemsBetween[0]))
          } else {
            // Already at group head — jump to the group before ownSep
            const sepsBefore = sepsBeforeCurrent.slice(0, -1)
            if (sepsBefore.length === 0) { this.focusListItem(0); return }
            const prevSep = sepsBefore[sepsBefore.length - 1]
            const firstAfterPrev = items.find(item =>
              prevSep.compareDocumentPosition(item) & Node.DOCUMENT_POSITION_FOLLOWING
            )
            if (firstAfterPrev) this.focusListItem(items.indexOf(firstAfterPrev))
            else this.focusListItem(0)
          }
        }
        return
      }
      if (action.name === "list_item_delete" || action.name === "list_item_archive") {
        const item = this.currentListItems()[this.listFocusIndex]
        if (!item) return
        const itemType = item.dataset.vimItemType
        const itemId = item.dataset.vimItemId
        const isArchive = action.name === "list_item_archive"
        // Determine event name based on entity type (or fall back to session for untagged items)
        let event: string
        let payload: Record<string, unknown>
        if (itemType && itemId) {
          event = isArchive ? `archive_${itemType}` : `delete_${itemType}`
          payload = { item_type: itemType, item_id: itemId }
          // Keep session_id for backwards compat when type is session
          if (itemType === "session") payload.session_id = itemId
        } else {
          // Backwards compat: untagged item — fall back to session behavior
          const sessionId = item.dataset.sessionId
          if (!sessionId) return
          event = isArchive ? "archive_session" : "delete_session"
          payload = { session_id: sessionId }
        }
        // TODO: LiveView handlers needed for archive_note/delete_note/archive_task/delete_task
        const savedIndex = this.listFocusIndex
        const obs = new MutationObserver(() => {
          if (item.isConnected) return
          obs.disconnect()
          const items = this.currentListItems()
          if (items.length === 0) { this.listFocusIndex = -1; return }
          this.focusListItem(Math.min(savedIndex, items.length - 1))
        })
        obs.observe(document.body, { childList: true, subtree: true })
        setTimeout(() => obs.disconnect(), 3000)
        this.pushToList?.(event, payload)
        return
      }
    }
  },

  enterHintMode(): void {
    const items = this.currentListItems()
    if (items.length === 0) return
    this.exitHintMode() // clear any stale overlay
    const labels = _generateHintLabels(items.length)
    this.hintLabels = labels.map((label, i) => ({ label, index: i }))
    this.hintBuffer = ""
    this.hintMode = true

    const overlay = document.createElement("div")
    overlay.id = "vim-nav-hints"
    overlay.style.cssText = "position:fixed;inset:0;pointer-events:none;z-index:9999"
    this.hintOverlayEl = overlay

    items.forEach((item, i) => {
      const rect = item.getBoundingClientRect()
      const badge = document.createElement("span")
      badge.dataset.hintLabel = labels[i]
      badge.textContent = labels[i]
      badge.style.cssText = [
        "position:fixed",
        `top:${rect.top + 4}px`,
        `left:${rect.left + 4}px`,
        "background:var(--color-warning,#f59e0b)",
        "color:var(--color-warning-content,#000)",
        "font-family:monospace",
        "font-size:11px",
        "font-weight:700",
        "line-height:1",
        "padding:1px 4px",
        "border-radius:3px",
        "pointer-events:none",
        "z-index:9999",
        "letter-spacing:0.05em",
      ].join(";")
      overlay.appendChild(badge)
    })

    document.body.appendChild(overlay)
    if (this.statusbarEl) {
      this.statusbarEl.textContent = "[ HINT ]"
      this.statusbarEl.style.color = "var(--color-warning, #f59e0b)"
      this.statusbarEl.style.opacity = "1"
    }
  },

  exitHintMode(): void {
    this.hintMode = false
    this.hintBuffer = ""
    this.hintLabels = []
    if (this.hintOverlayEl) {
      this.hintOverlayEl.remove()
      this.hintOverlayEl = null
    }
    if (this.statusbarEl) updateStatusbar(this.statusbarEl, this.mode, this.count)
  },

  _updateHintFilter(): void {
    if (!this.hintOverlayEl) return
    const prefix = this.hintBuffer

    // Find all matching labels
    const matches = this.hintLabels.filter(h => h.label.startsWith(prefix))

    if (matches.length === 0) {
      this.exitHintMode()
      return
    }

    // Update badge visibility
    this.hintOverlayEl.querySelectorAll<HTMLElement>("[data-hint-label]").forEach(badge => {
      const label = badge.dataset.hintLabel!
      if (label.startsWith(prefix)) {
        badge.style.opacity = "1"
        // Bold the typed prefix, normal for remaining chars
        const typed = label.slice(0, prefix.length)
        const rest = label.slice(prefix.length)
        badge.innerHTML = typed
          ? `<span style="opacity:0.5">${typed}</span>${rest}`
          : label
      } else {
        badge.style.opacity = "0.15"
      }
    })

    // Exact match — focus and exit
    if (matches.length === 1 && matches[0].label === prefix) {
      this.focusListItem(matches[0].index)
      this.exitHintMode()
    }
  },

  _recordSessionVisit() {
    const m = window.location.pathname.match(/^\/dm\/([0-9a-f-]{36})/)
    if (!m) return
    const uuid = m[1]
    const name = document.title || uuid.slice(0, 8)
    try {
      const key = "vim-nav:recent-sessions"
      const existing: Array<{ uuid: string; name: string }> = JSON.parse(sessionStorage.getItem(key) || "[]")
      const updated = [{ uuid, name }, ...existing.filter(s => s.uuid !== uuid)].slice(0, 20)
      sessionStorage.setItem(key, JSON.stringify(updated))
    } catch { /* ignore quota/parse errors */ }
  },

  showHelp(prefix?: string[]) {
    if (this.helpOverlayEl) { this.hideHelp(); return }

    const overlay = document.createElement("div")
    overlay.id = "vim-nav-help"
    overlay.setAttribute("aria-label", "Keyboard shortcuts")
    overlay.style.cssText = [
      "position:fixed","inset:0","z-index:10000",
      "display:flex","align-items:center","justify-content:center",
      "background:rgba(0,0,0,0.6)",
    ].join(";")

    const kbdStyle = "display:inline-block;padding:1px 5px;border:1px solid var(--color-base-300);border-radius:3px;font-size:10px;background:var(--color-base-200);color:var(--color-base-content)"

    let html = `<div style="background:var(--color-base-100);border:1px solid var(--color-base-300);border-radius:8px;padding:20px 24px;max-width:580px;width:90%;max-height:80vh;overflow-y:auto;font-family:monospace;color:var(--color-base-content)">`

    if (prefix && prefix.length > 0) {
      // Scoped help: show all commands under the given prefix
      const prefixCmds = COMMANDS.filter(cmd =>
        cmd.keys.length > prefix.length &&
        prefix.every((k, i) => cmd.keys[i] === k) &&
        isCommandActive(cmd)
      )
      const prefixLabel = prefix.join(" ")
      html += `<div style="font-size:13px;font-weight:600;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--color-base-300)">${escapeHtml(prefixLabel)} → Help</div>`

      const useGrid = prefixCmds.length > 8
      if (useGrid) html += `<div style="display:grid;grid-template-columns:1fr 1fr;column-gap:16px">`
      for (const cmd of prefixCmds) {
        const relKeys = cmd.keys.slice(prefix.length).map(k => `<kbd style="${kbdStyle}">${escapeHtml(k)}</kbd>`).join(" ")
        html += `<div style="display:flex;justify-content:space-between;align-items:center;padding:2px 0"><span style="font-size:11px;opacity:.8">${escapeHtml(cmd.label)}</span><span style="white-space:nowrap;padding-left:8px">${relKeys}</span></div>`
      }
      if (useGrid) html += `</div>`
    } else {
      // Global help: grouped by section
      const activeCmds = COMMANDS.filter(cmd => !cmd.id.startsWith("leader.") && isCommandActive(cmd))

      type Section = { label: string; group: string }
      const sections: Section[] = [
        { label: "Global",       group: "global" },
        { label: "Go to page",   group: "navigation" },
        { label: "Toggle rail",  group: "toggle" },
        { label: "Create",       group: "create" },
        { label: "Context",      group: "context" },
      ]

      html += `<div style="font-size:13px;font-weight:600;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--color-base-300)">Keyboard Shortcuts</div>`

      for (const section of sections) {
        const cmds = activeCmds.filter(c => c.group === section.group)
        if (cmds.length === 0) continue

        html += `<div style="margin-bottom:10px"><div style="font-size:9px;text-transform:uppercase;letter-spacing:.1em;color:var(--color-primary,var(--color-base-content));opacity:.7;margin-bottom:5px;font-weight:600">${escapeHtml(section.label)}</div>`

        const useGrid = cmds.length > 6
        if (useGrid) html += `<div style="display:grid;grid-template-columns:1fr 1fr;column-gap:16px">`
        for (const cmd of cmds) {
          const keys = cmd.keys.map(k => `<kbd style="${kbdStyle}">${escapeHtml(k)}</kbd>`).join(" ")
          html += `<div style="display:flex;justify-content:space-between;align-items:center;padding:2px 0"><span style="font-size:11px;opacity:.8">${escapeHtml(cmd.label)}</span><span style="white-space:nowrap;padding-left:8px">${keys}</span></div>`
        }
        if (useGrid) html += `</div>`
        html += `</div>`
      }
    }

    html += `<div style="margin-top:8px;font-size:9px;opacity:.4;text-align:center">Press any key to close</div></div>`
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

  showWhichKey(prefix: string[], delay = 300) {
    if (this.whichKeyTimer) clearTimeout(this.whichKeyTimer)
    this.whichKeyTimer = setTimeout(() => this._renderWhichKey(prefix), delay)
  },

  _renderWhichKey(prefix: string[]) {
    this.whichKeyTimer = null
    // Cancel the sequence auto-dismiss — overlay stays until user acts
    if (this.sequenceTimer) { clearTimeout(this.sequenceTimer); this.sequenceTimer = null }
    this.whichKeyEl?.remove()
    this.whichKeyEl = null

    const prefixCmds = COMMANDS.filter(cmd =>
      cmd.keys.length > prefix.length &&
      prefix.every((k, i) => cmd.keys[i] === k) &&
      isCommandActive(cmd)
    )
    if (prefixCmds.length === 0) return

    // Group by next key, then classify as terminal (direct action) or sub-group
    const byNextKey = new Map<string, Command[]>()
    for (const cmd of prefixCmds) {
      const nk = cmd.keys[prefix.length]
      if (!byNextKey.has(nk)) byNextKey.set(nk, [])
      byNextKey.get(nk)!.push(cmd)
    }

    type Entry = { key: string; label: string; subgroup: boolean }
    const entries: Entry[] = []

    // Labels for Space leader sub-groups at depth 1
    const SPACE_SUB_LABELS: Record<string, string> = {
      g: "go to page", t: "toggle rail", n: "create",
      b: "buffer/sessions", s: "search", x: "exit",
    }
    const GROUP_LABELS: Record<string, string> = {
      navigation: "go to page", toggle: "toggle rail", create: "create",
      global: "global", context: "context",
    }

    for (const [nk, cmds] of byNextKey) {
      const terminal = cmds.filter(c => c.keys.length === prefix.length + 1)
      const deeper  = cmds.filter(c => c.keys.length  > prefix.length + 1)
      for (const cmd of terminal) {
        entries.push({ key: nk, label: cmd.label, subgroup: false })
      }
      if (deeper.length > 0) {
        let subLabel: string
        if (prefix[0] === "Space" && prefix.length === 1) {
          subLabel = SPACE_SUB_LABELS[nk] ?? nk
        } else {
          subLabel = GROUP_LABELS[deeper[0]?.group ?? ""] ?? nk
        }
        entries.push({ key: nk, label: subLabel, subgroup: true })
      }
    }

    const overlay = document.createElement("div")
    overlay.id = "vim-nav-which-key"
    overlay.setAttribute("aria-hidden", "true")

    const useGrid = entries.length > 8
    overlay.style.cssText = [
      "position:fixed",
      "top:50%",
      "left:50%",
      "transform:translate(-50%,-50%)",
      "z-index:9999",
      "font-family:monospace",
      "font-size:12px",
      "background:var(--color-base-200)",
      "border:1px solid var(--color-base-300)",
      "border-radius:6px",
      "padding:10px 14px",
      "pointer-events:none",
      "color:var(--color-base-content)",
      "min-width:240px",
      "max-width:520px",
    ].join(";")

    const kbdStyle = "display:inline-block;padding:1px 5px;border:1px solid var(--color-base-300);border-radius:3px;font-size:11px;background:var(--color-base-100);color:var(--color-base-content);min-width:18px;text-align:center"
    const arrowStyle = "opacity:.35;margin:0 4px"

    const header = document.createElement("div")
    header.style.cssText = "font-size:10px;opacity:.5;margin-bottom:6px;text-transform:uppercase;letter-spacing:.08em;border-bottom:1px solid var(--color-base-300);padding-bottom:4px"
    header.textContent = `${prefix.join(" ")} →`
    overlay.appendChild(header)

    const container = document.createElement("div")
    container.style.cssText = useGrid
      ? "display:grid;grid-template-columns:1fr 1fr;gap:2px 20px"
      : "display:flex;flex-direction:column;gap:2px"

    for (const entry of entries) {
      const row = document.createElement("div")
      row.style.cssText = "display:flex;align-items:center"
      if (entry.subgroup) {
        row.innerHTML = `<kbd style="${kbdStyle}">${escapeHtml(entry.key)}</kbd><span style="${arrowStyle}">→</span><span style="color:var(--color-primary,var(--color-base-content));opacity:.9">+${escapeHtml(entry.label)}</span>`
      } else {
        row.innerHTML = `<kbd style="${kbdStyle}">${escapeHtml(entry.key)}</kbd><span style="${arrowStyle}">→</span><span style="opacity:.8">${escapeHtml(entry.label)}</span>`
      }
      container.appendChild(row)
    }
    overlay.appendChild(container)

    document.body.appendChild(overlay)
    this.whichKeyEl = overlay
  },

  hideWhichKey() {
    if (this.whichKeyTimer) { clearTimeout(this.whichKeyTimer); this.whichKeyTimer = null }
    this.whichKeyEl?.remove()
    this.whichKeyEl = null
  },
}

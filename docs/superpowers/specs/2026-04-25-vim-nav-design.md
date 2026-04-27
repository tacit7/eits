# Vim-Style App Navigation for EITS

**Date:** 2026-04-25  
**Scope:** App-level keyboard navigation — Vimperator-style normal/insert modes, `g`/`t`/`n` prefix keymaps, which-key hint overlay, statusbar. Power-user layer, opt-in for MVP.

---

## Architecture

A single TypeScript module `assets/js/hooks/vim_nav.ts` exported as a Phoenix LiveView hook, mounted on the **persistent app shell component** (the authenticated layout wrapper that owns the rail, topbar, project picker, and overlays).

The hook owns:
- **Mode state** — `"normal"` | `"insert"`, initialized from current focus state on mount
- **Key sequence buffer** — accumulates multi-key sequences with separate timers for hint display (300ms) and expiry (1000ms)
- **Command registry** — data-driven map of all bindings (`vim_nav_commands.ts`)
- **DOM singletons** — statusbar and which-key overlay, injected into `<body>` on `mounted()`, removed in `destroyed()`

Panel/flyout toggles dispatch events to the **app shell**. Per-page commands declare an explicit scope and target. Unsupported scoped commands no-op with a small hint.

---

## App Shell Contract

The VimNav hook mounts on the authenticated app shell element:

```heex
<div id="app-shell" phx-hook="VimNav" data-vim-nav-enabled={@vim_nav_enabled}>
  ...
</div>
```

The shell must own or expose handlers for:
- navigation
- command palette
- project picker
- rail section toggles
- modal/drawer open/close
- global help

Per-page commands must declare an explicit scope and must no-op with a visible hint if the current page does not support them.

---

## Mode Model

**Normal mode** (default resting state)
- App boots here if no editable element is focused
- VimNav intercepts only recognized bindings and active prefix sequences; unknown keys, browser shortcuts, modifier chords, composition events, and already-prevented events pass through untouched
- `Esc` clears the active key sequence and hides VimNav overlays. If a VimNav-owned transient overlay is open, it closes that overlay. If focus is inside an editable app element, `Esc` blurs it and returns to normal mode. CodeMirror is ignored until MVP 4.

**Insert mode**
- Entered automatically via `focusin` on any input, textarea, select, contenteditable, or `role="textbox"`
- Exited via `Esc` — blurs the element, returns to normal mode
- All keys pass through untouched

**Mount behavior**
On `mounted()` and after LiveView reconnects, detect current state rather than assuming normal:
```ts
this.mode = isEditableTarget(document.activeElement) ? "insert" : "normal"
```

**Key interception guard** — two-phase to correctly handle `Esc` in insert mode:
```ts
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

// Phase 2: normal mode — guard then dispatch
if (event.metaKey || event.ctrlKey || event.altKey) return
if (isEditableTarget(event.target)) return
if (!matchesKnownBindingOrPrefix(event)) return
event.preventDefault()
```

Key normalization — handle shift for `?` and similar:
```ts
function keyFromEvent(event: KeyboardEvent): string {
  if (event.key === " ") return "Space"
  return event.key.length === 1 ? event.key.toLowerCase() : event.key
}
```

**CodeMirror:** Out of scope for MVP 1–3. VimNav treats CM as a black box — all CM key events are ignored.

---

## Command Registry

All bindings declared in `assets/js/hooks/vim_nav_commands.ts`. No hardcoded event names in the hook.

```ts
type Command = {
  id: string
  label: string
  keys: string[]
  group: "navigation" | "toggle" | "create" | "global" | "context"
  action: CommandAction
  scope?: string   // e.g. "global", "route:/tasks", "feature:vim-list"
}

type CommandAction =
  | { kind: "navigate"; path: string }
  | { kind: "push_event"; event: string; payload?: object; target: "shell" | "active_view" }
  | { kind: "client"; name: "command_palette" | "help" | "history_back" | "history_forward" }
```

The which-key overlay and `?` help screen are generated from this registry. Commands whose scope does not match the current context are hidden and disabled. Adding a binding = adding one registry entry.

---

## Keymap

### `g` — page navigation

| Key | Destination |
|-----|-------------|
| `g s` | `/sessions` |
| `g t` | `/tasks` |
| `g n` | `/notes` |
| `g w` | `/canvas` |
| `g a` | `/agents` |
| `g ,` | `/settings` |

### `t` — toggle rail sections / flyouts

| Key | Action |
|-----|--------|
| `t s` | Sessions section (`toggle_section: sessions`) |
| `t t` | Tasks section (`toggle_section: tasks`) |
| `t n` | Notes section (`toggle_section: notes`) |
| `t f` | Files flyout (`toggle_section: files`) |
| `t w` | Canvas panel (`toggle_section: canvas`) |
| `t c` | Chat (`toggle_section: chat`) |
| `t k` | Skills section (`toggle_section: skills`) |
| `t m` | Teams section (`toggle_section: teams`) |
| `t j` | Jobs section (`toggle_section: jobs`) |
| `t p` | Project switcher (`toggle_proj_picker`) |

### `n` — create

| Key | Action |
|-----|--------|
| `n s` | New session |
| `n t` | New task (`toggle_new_task_drawer`) |
| `n a` | New agent drawer (`toggle_new_agent_drawer`) |
| `n n` | New note (`open_quick_note_modal`) |

### Single keys

| Key | Action | MVP |
|-----|--------|-----|
| `?` | Full keybinding help overlay (generated from registry) | 1 |
| `:` | Open command palette | 2 |
| `/` | Page search (`data-vim-search`) or command palette | 3 |
| `[` | `history.back()` | 3 |
| `]` | `history.forward()` | 3 |
| `j` | Next item in active `data-vim-list` | 3 |
| `k` | Previous item in active `data-vim-list` | 3 |
| `Enter` | Open focused item | 3 |

### Flyout list behavior (MVP 3)

Pages opt in by marking one list with `data-vim-list`. Pages register search with `data-vim-search`. The hook does not guess by querying DOM elements.

When `data-vim-list` is active:
- `j`/`k` move through items in that list only; no-op otherwise
- `Enter` navigates to item; flyout stays open
- `Esc` closes flyout, returns focus to page

### Context-specific (MVP 3)

| Key | Action | Context |
|-----|--------|---------|
| `f f` | Toggle filter drawer | Tasks / kanban pages |
| `a d` | Toggle agent drawer | Chat page |
| `m b` | Toggle members panel | Chat page |

---

## Which-key Overlay

Two separate timers:
- **300ms after prefix key** — overlay appears showing available second keys for the active prefix
- **1000ms after prefix key** — sequence expires; buffer clears; overlay hides

**MVP 1** includes only the `?` static help overlay (full registry dump).  
**MVP 2** adds the timed which-key prefix hints for `g`, `t`, `n`.

Overlay dismisses instantly on any keypress. No animation. Content generated from registry filtered to active prefix and current scope.

---

## Statusbar

Fixed position, bottom-right corner. Always visible when Vim nav is enabled.

- `[ NORMAL ]` — dim, unobtrusive
- `[ INSERT ]` — slightly brighter

Single line, monospace, `text-xs`. Sits above DaisyUI toasts. `aria-hidden="true"`.

---

## Failure Behavior

Commands must fail safely:
- Unknown key sequences clear the buffer and show a small "unknown binding" hint
- Commands with unmet scope requirements no-op and show a small hint
- Navigation commands do nothing if the current route already matches the destination
- Live events that cannot be dispatched to the expected target log a dev warning and no-op in production
- VimNav must never throw uncaught errors from a keydown handler

---

## Route Awareness

The hook reads `window.location.pathname` and optional shell-provided metadata to evaluate command scope.

Scope values:
- `"global"` — always active
- `"route:/tasks"` — exact route match
- `"route_prefix:/projects"` — prefix match
- `"feature:vim-list"` — page has `data-vim-list` present
- `"feature:page-search"` — page has `data-vim-search` present

Commands with unmatched scope are hidden from which-key and disabled in the `?` help overlay.

---

## Lifecycle — `destroyed()`

Must remove on cleanup:
- `keydown` listener
- `focusin` listener
- `focusout` listener
- All active timers (`clearTimeout`)
- Injected statusbar element
- Injected which-key overlay element

---

## Accessibility

- Vim navigation is **opt-in for MVP**; the setting persists in localStorage and may later sync to user preferences
- `event.isComposing` check prevents IME interference
- Modifier chords pass through untouched
- Unknown keys pass through untouched — VimNav is additive, not a keyboard trap
- `?` help screen is reachable via visible UI (settings or help button), not keyboard only
- Overlay and statusbar use sufficient contrast for dark and light themes

---

## Testing / QA Checklist

- Typing in inputs never triggers navigation
- `Esc` in an input exits insert mode and blurs the input
- `Esc` in CodeMirror is ignored by VimNav
- `g s` navigates to sessions from every authenticated page
- Unknown keys pass through without `preventDefault`
- `Cmd+R`, `Cmd+L`, `Cmd+F`, `Ctrl+C` are not intercepted
- IME composition input is not intercepted
- LiveView reconnect does not duplicate listeners or DOM nodes
- Disabling Vim navigation removes key handling; normal app navigation stays intact
- `?` help accurately reflects the command registry

---

## Implementation Notes

- `vim_nav.ts` at `assets/js/hooks/vim_nav.ts`
- `vim_nav_commands.ts` at `assets/js/hooks/vim_nav_commands.ts`
- Register hook in `assets/js/hooks/index.ts`
- Mount via `phx-hook="VimNav"` on the persistent app shell (`id="app-shell"`)
- Statusbar and overlay are plain DOM — no Svelte, no LiveView component

---

## MVP Phases

### MVP 1 — Safe global navigation
- Enable/disable setting (opt-in, localStorage)
- Hook lifecycle with `destroyed()` cleanup
- Normal/insert mode with focus-based detection on mount
- Two-phase key guard
- Statusbar
- `g` navigation group
- `?` static help overlay (full registry)
- `Esc` behavior (sequence clear + conditional blur)

### MVP 2 — Toggles, creation, command palette
- `t` toggles
- `n` creation actions
- `:` command palette
- Which-key timed overlay for `g`, `t`, `n`
- `[` / `]` history navigation

### MVP 3 — Context-aware page behavior
- Page opt-in `data-vim-list` and `data-vim-search`
- `j/k/Enter` flyout list navigation
- `/` page search integration
- Context-specific page bindings (`f f`, `a d`, `m b`)
- Scope-aware command filtering in which-key and help

### MVP 4 — CodeMirror integration
- Explicit CM boundary rules
- Editor escape behavior (`Ctrl+[` or double-`Esc`)
- File viewer shortcuts
- Only after MVP 1–3 are stable

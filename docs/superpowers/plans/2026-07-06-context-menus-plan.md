# Context Menus for Cards — Plan

**Date:** 2026-07-06 · **Status:** Draft for approval · **Task:** 8195

## Goal

Right-click context menus on entity cards/rows across the app: sessions, tasks (kanban + list), notes, and later agents/teams. One implementation that works in the browser AND the desktop webview.

## Architecture decision (the one that matters)

**Web-first shared context menu, one action bridge.** Today's only context menu is the native Tauri popup on rail session rows (`show_session_context_menu` in Rust) — it's desktop-only, requires Rust changes per entity type, and browser users get nothing. Scaling native menus to tasks/notes/teams means a Rust command + menu-builder per entity, forever.

Instead:

- **One JS-rendered menu component** (positioned overlay, dark-theme, DaisyUI-styled) driven by a single delegated `contextmenu` listener.
- **Declarative opt-in:** any card adds `data-ctx="session" data-ctx-id={id}` plus entity payload attrs (`data-ctx-name`, `data-ctx-worktree`, …). No per-page JS.
- **One action bridge:** menu items dispatch the existing `tauri:session-action`-style CustomEvents — generalized to `ctx-action` — which a hook forwards to the owning LiveView via `pushEventTo`. The Rust menu already speaks this protocol for archive/rename, so server-side handlers get reused, not rewritten.
- **Tauri-native actions** (Open in Finder, new window, clipboard) go through the existing `invoke` bridges when `data-env="tauri"`, hidden in the browser.
- **Retire the native session menu** once the web menu reaches parity on flyout rows — one codepath, consistent look, and browser users finally get menus. (Flag: we lose the OS-native look in the desktop app; I think consistency wins.)

## Menu registry (initial actions)

| Entity | Actions |
|---|---|
| **Session** card/row | Open · Open in New Window (tauri) · Rename · Archive · Mark unread¹ · Copy session ID · Copy deeplink · Open worktree in Finder (tauri) · DM this session |
| **Task** card (kanban/list) | Open · Move to → (To Do / In Progress / In Review / Done) · Claim · Complete… · Copy task ID · Delete |
| **Note** | Open · Star/Unstar · Copy note ID · Delete |
| **Agent** (later) | Open · Copy agent UUID · Spawn with this def |

¹ "Mark unread" is a stub in the native menu today ("Coming soon" flash) — keep parity, don't build the feature.

## Phases (each = one EITS task, mockup-first per project convention)

**Phase 0 — Mockup.** `priv/static/mockups/context-menus.html`: menu anatomy (items, separators, submenu for task states, destructive styling for Delete/Archive), per-entity variants, and touch/long-press note. Review gate before code.

**Phase 1 — Core (the real work).** `ContextMenu` hook + overlay component in the app layout:
- delegated `contextmenu` listener; closest `[data-ctx]` wins; `preventDefault` only when a registry entry matches (native browser menu everywhere else)
- registry: JS module mapping entity type → item list (label, icon, action, tauri-only?, destructive?, submenu)
- positioning (viewport-clamped), Escape/click-away/scroll to close, arrow-key navigation + Enter, `role="menu"` a11y
- action dispatch: `ctx-action` CustomEvent + the pushEvent bridge; clipboard + invoke paths for tauri-only items
- long-press (~500ms) opens it on touch devices

**Phase 2 — Sessions everywhere.** Wire `data-ctx="session"` into `session_card.ex`, agent list rows, and the rail flyout rows. Server: reuse the existing archive/rename handlers; add copy-deeplink/DM navigation items. Kill switch comparison vs the native menu, then remove `show_session_context_menu` + its app.js block + the Rust command (separate commit, easy revert).

**Phase 3 — Tasks.** `data-ctx="task"` on kanban cards + task list rows. Server handlers: state moves (reuse workflow-state update paths), claim/complete/delete with confirm on destructive. Kanban bulk-select interplay: right-click on a selected card acts on the selection (stretch — flag if it complicates, do single-card first).

**Phase 4 — Notes + polish.** Notes wiring; then the long tail: submenu keyboard nav, menu-key (Shift+F10) support, per-page custom items API if a page needs an extra action.

## Testing

- Phase 1: vitest for registry/positioning logic; Playwright: right-click opens, Escape closes, action round-trip (rename pushes event), tauri-only items hidden in browser.
- Per-entity phases: Playwright action round-trips against the worktree dev server; `mix compile --warnings-as-errors` gate.

## Estimate

Phase 0+1 ≈ one focused session (the core is the cost). Phases 2–3 ≈ a session together. Phase 4 opportunistic.

## Out of scope

Mark-unread feature itself, bulk-selection menus beyond the stretch note, native OS menus for non-session entities, mobile drawer redesign.

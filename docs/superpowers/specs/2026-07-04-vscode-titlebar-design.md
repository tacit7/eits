# VS Code-style Title Bar — Design

**Date:** 2026-07-04 · **Status:** Approved (mockup Variant B: `priv/static/mockups/vscode-titlebar.html`) · **Task:** 8100

## Layout

`app.html.heex` becomes 3 rows: new `#app-vsbar` (full-width, `h-[38px]`, `hidden md:flex`) → existing rail+main flex row → page content. Mobile keeps its current header, unaffected.

- `data-tauri-drag-region` moves from `#app-topbar` to `#app-vsbar` (same app.js mousedown handler; interactive children excluded as today).
- Traffic-light clearance: `html[data-env="tauri"] #app-vsbar { padding-left: 72px }`; remove `.app-titlebar` 72px rail padding and `#app-topbar`'s `pl-20` (topbar reverts to normal padding).
- Web build renders the same bar without the padding (gated on `data-env`).

## Contents (left → right)

| Element | Source / action |
|---|---|
| Crumb `{project} › {section}` | same assigns as rail (`sidebar_project`, `sidebar_tab`); coarse only — detailed breadcrumb stays in `#app-topbar` |
| Command-center pill (absolute-centered) | `JS.dispatch("palette:open", to: "#command-palette")`, shows ⌘K hint |
| Status pill | port from `location.port` (client-side); dot bound to `html[data-socket]` set by LiveSocket connect/disconnect in app.js |
| Bell | same enable-push button as mobile header |
| Rail toggle | existing `sidebar_collapsed` toggle (app.js:267 path) |
| Always-on-top pin | new Tauri command `set_always_on_top(on: bool) -> bool` + `get_always_on_top()` reading the existing `ALWAYS_ON_TOP` static; pin rendered only under `data-env="tauri"`; menu/tray checkmarks stay consistent (same static) |

## Out of scope

New-window button, per-page vsbar toolbars, mobile variant, rail-collapse redesign.

## Verification

- `mix compile --warnings-as-errors`; visual check via dev server (browser) and `cargo tauri dev` for traffic-light alignment; `cargo check` for the Rust command.
- Pin requires a Rust rebuild — ships last; the bar itself is pure Phoenix.

# Vim-Nav: LazyVim-Inspired Keybindings Plan

Status: **draft / proposal**
Owner: vim-nav feature
Last updated: 2026-04-28

This is the design doc for adapting [LazyVim](https://www.lazyvim.org/) idioms into the EITS web vim-nav system. It is the source of truth for *what* we will bind before we touch *how*.

---

## Goals

1. Reduce keystrokes for the highest-frequency actions.
2. Reuse muscle memory from LazyVim users.
3. Stay consistent with the rest of vim-nav (sequence-based, scope-aware, no modes beyond NORMAL/INSERT).
4. No regressions on existing bindings — net additions only.

## Non-goals

- Faithful Neovim feature parity (LSP, terminals, registers, marks, macros, ex commands).
- Full text-editing modal model. We are still a *navigation* layer, not a Vim emulator.
- Plugin-specific bindings that don't have a web-app analog (Trouble, Lazy, Mason).

---

## Core LazyVim concepts and how they map here

| LazyVim concept | EITS web analog | Notes |
|---|---|---|
| `<leader>` = `Space` | New: `Space` as a registered prefix | Currently bound only as `keyFromEvent("Space")`; nothing dispatches on it. Will become the primary modal prefix. |
| Buffers | Sessions / tabs | Buffer cycling = session list cycling. |
| Windows | Flyouts + main pane | We don't have true tiled windows. Treat the rail flyout as a "window". |
| LSP `gd` / `gr` / `gI` | n/a | Skip — no language server. |
| `[d` / `]d` (diagnostic) | Failed agents / errored sessions | Superseded by `(` `)` approach — see Phase B. |
| `[b` / `]b` (buffer) | Sessions list nav | Superseded by `(` `)` approach — see Phase B. |
| `<C-h/j/k/l>` (window nav) | Flyout vs main focus toggle | Repurposed: focus rail vs focus main view. |
| `<S-h>` / `<S-l>` | Prev / next session | Cut — see Phase C. |
| `<leader>e` (explorer) | Toggle Files flyout (`tf`) | Add `Space e` as alias. |
| `<leader>ff` (find files) | Open command palette filtered to files | Deferred — not Phase 1. |
| `<leader>fr` (recent) | Recent files opened in CodeMirror file editor | Phase 1: open most recently edited file in the editor. |
| `<leader>sg` (grep) | Global search | Deferred — will integrate with command palette autocomplete. |
| `<leader>w` (save) | Save in file editor | Only relevant when CodeMirror has focus — probably handled by CodeMirror, not us. |
| `<leader>qq` (quit all) | Close current flyout / dialog | Currently `q`. |

---

## Proposed bindings (Phase A — Leader infrastructure)

The leader is `Space`. Pressing `Space` enters a 2s sequence window and shows the which-key overlay.

### `<leader>` quick actions (single-key after Space)

| Keys | Action | Notes |
|---|---|---|
| `Space e` | Toggle Files flyout | Alias of `tf`. LazyVim: explorer. |
| `Space q` | Close flyout | Alias of `q` for users with leader muscle memory. |
| `Space w` | (reserved) | Save in editor — no-op in nav layer; reserved so we don't grab it. |
| `Space ,` | Last visited session | New behavior: jump to most recently visited session (window history). |
| `Space :` | Command palette | Alias of `:`. |
| `Space ?` | Keybinding help overlay | Alias of `?`. |
| `Space n` | New (chord prefix below) | `Space n a` = new agent, etc. — mirror existing `n a`/`n t`/`n n`/`n c`. |

### `Space f` — Files (Phase 1 only)

| Keys | Action |
|---|---|
| `Space f r` | Open most recently edited file in CodeMirror file editor |
| `Space f t` | Toggle file editor full-viewport |

> Phase 1 scope: `ff` (find files via palette) and `fg` (global grep) are deferred. `fr` targets the file editor's own recent history, not a general session/notes list.

### `Space s` — Search (Phase 1: minimal)

| Keys | Action |
|---|---|
| `Space s s` | Focus current page search (alias of `/`) |

> Deferred: `Space s g` global grep, `Space s a/t/n` entity search. These will hook into command palette autocomplete when that's built. For Phase 1, `Space s s` is the only binding here.

### `Space b` — Buffer (sessions)

| Keys | Action |
|---|---|
| `Space b a` | Archive current session |
| `Space b D` | Hard-delete current session |

> Trimmed from original proposal. `Space b n/p/l` (next/prev/last) removed — too many keystrokes for high-frequency cycling. Cycling is handled by Phase B (`(` `)`). Archive and delete are lower-frequency destructive actions that justify 3 keystrokes.

### `Space x` — eXit / dismiss

| Keys | Action |
|---|---|
| `Space x x` | Close all flyouts and dialogs |

---

## Proposed bindings (Phase B — Single-key list cycling)

Replaces the original bracket-pair (`[ b`, `] b`) proposal. Bracket + letter combos are awkward and conflict with the existing single-key `[`/`]` history bindings. Instead, use `(` and `)` — single keys, currently unbound, naturally convey "previous/next cycle".

| Keys | Action | Scope |
|---|---|---|
| `(` | Previous item in current list | `feature:vim-list` |
| `)` | Next item in current list | `feature:vim-list` |
| `( d` | Previous failed/errored session | `page:sessions` |
| `) d` | Next failed/errored session | `page:sessions` |

Conflict check: `(` and `)` are not currently bound. No timer disambiguation needed — they are unambiguous single keys. The `( d` / `) d` variants follow the same sequence-timer pattern as other multi-key commands.

> The original `[ b`/`] b`/`[ a`/`] a` table is dropped. List cycling via `(` `)` is global on any vim-list page, which covers sessions, tasks, notes, and agents without needing per-entity variants.

---

## Phase C — Dropped

`H` / `L` (Shift-letter session cycling) cut entirely. Not worth the shift-key overhead when `(` `)` in Phase B handle the same use case more cleanly.

---

## Implementation work (no rewrite required)

1. **`keyFromEvent`**: encode modifiers when present (`"C-h"` for Ctrl+H, `"M-x"` for Meta+X). For our Phase A–B plan we only need shift handling, which already works via `event.key` casing — Ctrl/Meta deferred until we actually need them.
2. **`handleKey`**: stop unconditionally bailing on `ctrlKey/metaKey` — only bail when no command exists for that combo. Phase A–B don't need this; defer.
3. **`PREFIXES`**: already a `Set` of `keys[0]`. Add `"Space"` once Space-prefixed commands exist.
4. **`_renderWhichKey`**: extend to handle 3+ key chords. Currently filters `cmd.keys[0] === prefix && cmd.keys.length > 1`. Need to handle the case where the buffer is `["Space", "f"]` and we want which-key for the third key. Refactor `_renderWhichKey(prefix: string)` to `_renderWhichKey(prefix: string[])` so it filters on the buffer prefix array.
5. **Sequence timer**: already 1000ms — bump to 1500–2000ms when in a `Space`-led chord to give users time to think (LazyVim parity).
6. **`Space` as a key**: `keyFromEvent` returns `"Space"` for `" "` already.
7. **Help overlay grouping**: currently grouped by `cmd.group`. Add a "Leader" group label.
8. **`/keybindings` page**: add a "Leader (Space)" section.

---

## Conflicts with existing bindings

| Existing | Proposed | Resolution |
|---|---|---|
| `[` history_back | `(` / `)` list cycling | No conflict — different keys. |
| `]` history_forward | same | No conflict. |
| `q` close flyout | `Space q` close flyout | Both keep working. |
| `?` help | `Space ?` help | Both keep working. |
| `:` palette | `Space :` palette | Both keep working. |
| `n a`/`n t`/`n n`/`n c` create | `Space n a`/`t`/`n`/`c` | Both keep working. |
| `A`/`D` session archive/delete | `Space b a` / `Space b D` | Both keep working; leader versions are aliases. |

No removals. Net additions only.

---

## Open questions

1. Do we want `Space ,` (last-visited-session) at all? Requires session history tracking that we don't have today. Could defer.
2. `Space f r` recent files — does the CodeMirror file editor already track recently opened files, or do we need to add that? If no existing history, this needs a client-side recents list (localStorage).
3. `( d` / `) d` jump to failed session — worth it for Phase B, or defer until sessions page gets more keyboard love?
4. Should `Space` show which-key immediately (no 300ms delay) since it's clearly a leader, vs other prefixes? LazyVim's which-key fires immediately on leader. Probably yes — special-case `Space` to bypass the delay.

---

## Phasing

- **Phase A first** (leader): `Space e/q/,/:/? /n`, `Space f r/t`, `Space s s`, `Space b a/D`, `Space x x`. Needs which-key refactor and PREFIXES update.
- **Phase B** (single-key cycling): `(` `)` on vim-list pages. No infra changes, quick add.
- ~~Phase C~~ Cut.

---

## Test coverage targets

- All new bindings registered in `vim_nav_commands.ts` get a "command exists with correct keys/scope" test.
- Each new client action (e.g. `last_visited_session`, `next_failed_session`) gets an executeCommand test with DOM fixtures.
- which-key 3+ chord rendering gets a dedicated test.
- `Space` leader bypass of which-key delay gets a timing test.

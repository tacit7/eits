# Vim Navigation — Keybinding Reference

Opt-in keyboard navigation for the EITS web app. Enable in **Settings → General → Vim navigation**.

Source of truth: `assets/js/hooks/vim_nav_commands.ts`
In-app overlay: press `?` anywhere, or visit `/keybindings`.

## Help overlays

**Which-key overlay**: Press any prefix key (`Space`, `g`, `t`, `n`, etc.) to see available next keys and their actions in a floating overlay centered on screen. There is a 500ms delay before the overlay appears to prevent flicker during normal typing. Sub-groups show as entries with a `+` prefix (e.g., `Space g → +go to page`); direct actions show without the `+`. When there are more than 8 entries, the overlay switches to a 2-column grid for better readability.

**Sub-command help (`?` with active prefix)**: While a prefix is active (e.g., you've typed `Space` and are waiting to type the next key), press `?` to show scoped help for that prefix with relative key sequences instead of the full layout.

**Full help (`?`)**: Opens a full-page overlay organized by named sections (Global, Go to page, Toggle rail, Create, Context). Each section displays commands in its category; sections with more than 6 commands use a 2-column grid. Space leader aliases (e.g., `Space g`, `Space t`, `Space n`) are excluded to avoid duplication with base `g`, `t`, `n` bindings.

---

## Global (always active)

| Keys | Action |
|---|---|
| `?` | Keybinding help overlay |
| `:` | Command palette |
| `[` | Go back (browser history) |
| `]` | Go forward (browser history) |
| `q` | Close flyout |
| `/` | Focus search *(requires `data-vim-search` on page)* |

---

## Go to page — `g` prefix

| Keys | Destination |
|---|---|
| `g s` | Sessions |
| `g t` | Tasks |
| `g n` | Notes |
| `g a` | Agents |
| `g k` | Kanban |
| `g w` | Canvas |
| `g f` | Files |
| `g p` | Prompts |
| `g c` | Chat |
| `g j` | Jobs |
| `g u` | Usage |
| `g m` | Teams |
| `g K` | Skills |
| `g N` | Notifications |
| `g ,` | Settings |
| `g h` | Keybinding reference (this page) |

---

## Toggle rail section — `t` prefix

Lowercase toggles open/close. Uppercase toggles **and enters flyout focus** (same as pressing `F` after opening).

| Keys | Section | With focus |
|---|---|---|
| `t s` | Sessions | `t S` |
| `t t` | Tasks | `t T` |
| `t n` | Notes | `t N` |
| `t f` | Files | `t F` |
| `t w` | Canvas | `t W` |
| `t c` | Chat | `t C` |
| `t k` | Skills | `t K` |
| `t m` | Teams | `t M` |
| `t j` | Jobs | `t J` |
| `t a` | Agents | — |
| `t u` | Usage | — |
| `t b` | Notifications | — |
| `t P` | Prompts | — |
| `t p` | Project picker | — |

---

## Create — `n` prefix

| Keys | Action |
|---|---|
| `n a` | New agent |
| `n t` | New task |
| `n n` | New note |
| `n c` | New chat |
| `n p` | New prompt |
| `n k` | New kanban task *(kanban page only)* |

---

## List navigation

Active on any page with `data-vim-list`.

| Keys | Action |
|---|---|
| `j` | Next item |
| `k` | Previous item |
| `Enter` | Open focused item |

---

## Flyout navigation

Active when a flyout panel is open (`feature:vim-flyout` scope).

| Keys | Action |
|---|---|
| `F` | Enter flyout focus (then `j`/`k` navigate, `Enter` opens, `Esc` exits) |

---

## Sessions page — `page:sessions` scope

| Keys | Action |
|---|---|
| `A` | Archive focused session (refocuses next/previous item) |
| `D` | Delete focused session (refocuses next/previous item) |
| `y u` | Copy session UUID to clipboard |
| `y i` | Copy session integer ID to clipboard |

When a focused session is archived or deleted, vim-nav automatically refocuses to the next item in the list, or the last item if deleting at the end. This behavior uses a MutationObserver to detect when the focused element is removed from the DOM.

---

## Tasks page — `route_suffix:/tasks`

| Keys | Action |
|---|---|
| `j` / `k` | Navigate task list |
| `Enter` | Open focused task detail drawer |
| `f f` | Toggle filter drawer |

---

## Prompts page — `route_suffix:/prompts`

| Keys | Action |
|---|---|
| `j` / `k` | Navigate prompts list |
| `Enter` | Open focused prompt |

---

## Teams page — `route_suffix:/teams`

| Keys | Action |
|---|---|
| `j` / `k` | Navigate teams list |
| `Enter` | Open focused team detail page |

---

## Chat page — `route_suffix:/chat`

| Keys | Action |
|---|---|
| `a d` | Toggle agent drawer |
| `m b` | Toggle members panel |

---

## DM page — `route_suffix:/dm`

| Keys | Action |
|---|---|
| `i` | Focus message composer |

---

## Space leader

`Space` is the leader key. Pressing it opens a which-key overlay immediately. The sequence window is 2s (vs 1s for other prefixes).

### Quick actions (2-key)

| Keys | Action |
|---|---|
| `Space e` | Toggle Files flyout |
| `Space q` | Close flyout |
| `Space :` | Command palette |
| `Space ?` | Keybinding help |

### Find — `Space f`

| Keys | Action |
|---|---|
| `Space f s` | Find session (palette picker) |
| `Space f r s` | Find recent session (from visit history) |

### Search — `Space s`

| Keys | Action |
|---|---|
| `Space s s` | Focus search *(requires search on page)* |

### Buffer/sessions — `Space b`

| Keys | Action |
|---|---|
| `Space b a` | Archive session *(sessions page)* |
| `Space b D` | Delete session *(sessions page)* |

### Exit — `Space x`

| Keys | Action |
|---|---|
| `Space x x` | Close all flyouts |

### Go to page — `Space g` (aliases of `g` bindings)

| Keys | Destination |
|---|---|
| `Space g s` | Sessions |
| `Space g t` | Tasks |
| `Space g n` | Notes |
| `Space g a` | Agents |
| `Space g k` | Kanban |
| `Space g w` | Canvas |
| `Space g f` | Files |
| `Space g p` | Prompts |
| `Space g c` | Chat |
| `Space g j` | Jobs |
| `Space g u` | Usage |
| `Space g m` | Teams |
| `Space g K` | Skills |
| `Space g N` | Notifications |
| `Space g ,` | Settings |
| `Space g h` | Keybindings |

### Toggle rail — `Space t` (aliases of `t` bindings)

| Keys | Section |
|---|---|
| `Space t s` | Sessions |
| `Space t t` | Tasks |
| `Space t n` | Notes |
| `Space t f` | Files |
| `Space t w` | Canvas |
| `Space t c` | Chat |
| `Space t k` | Skills |
| `Space t m` | Teams |
| `Space t j` | Jobs |
| `Space t a` | Agents |
| `Space t u` | Usage |
| `Space t b` | Notifications |
| `Space t P` | Prompts |
| `Space t p` | Project picker |

### Create — `Space n` (aliases of `n` bindings)

| Keys | Action |
|---|---|
| `Space n a` | New agent |
| `Space n t` | New task |
| `Space n n` | New note |
| `Space n c` | New chat |
| `Space n p` | New prompt |
| `Space n k` | New kanban task *(kanban page only)* |

---

## Scope system

Scoped commands only fire when their scope condition is met.

| Scope | Active when |
|---|---|
| `feature:vim-list` | `[data-vim-list]` exists in DOM |
| `feature:vim-search` | `[data-vim-search]` exists in DOM |
| `feature:vim-flyout` | `[data-vim-flyout-open]` attribute is present |
| `page:sessions` | `[data-vim-page="sessions"]` exists in DOM |
| `route_suffix:/tasks` | `window.location.pathname` ends with `/tasks` |
| `route_suffix:/chat` | ends with `/chat` |
| `route_suffix:/dm` | ends with `/dm` |
| `page:tasks` | `/tasks` page (j/k navigation, filter toggle) |
| `page:prompts` | `/prompts` page (j/k navigation) |
| `page:teams` | `/teams` page (j/k navigation) |

---

## Visual styling

All list items with `data-vim-list-item` now use a consistent focused ring style: `ring-2 ring-primary/50`. This applies to:
- List items on sessions, tasks, prompts, teams, notes, kanban, and agents pages
- Flyout section items (sessions, notes, teams, agents, canvas, tasks, jobs, chat)

When a list item or flyout item is focused via `j`/`k` or direct vim-nav focus, the ring indicator displays consistently across all pages.

# Vim Navigation — Keybinding Reference

Opt-in keyboard navigation for the EITS web app. Enable in **Settings → General → Vim navigation**.

Source of truth: `assets/js/hooks/vim_nav_commands.ts`
In-app overlay: press `?` anywhere, or visit `/keybindings`.

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
| `A` | Archive focused session |
| `D` | Delete focused session |
| `y u` | Copy session UUID to clipboard |
| `y i` | Copy session integer ID to clipboard |

---

## Tasks page — `route_suffix:/tasks`

| Keys | Action |
|---|---|
| `f f` | Toggle filter drawer |

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

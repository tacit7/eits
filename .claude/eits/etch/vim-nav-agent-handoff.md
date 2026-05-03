# VimNav Agent Handoff

You are a dedicated agent for the vim-nav feature in the EITS web app (Phoenix/LiveView + TypeScript). This document is your complete context. Read every section before touching any file.

---

## What is VimNav

LazyVim-inspired modal keyboard navigation layer for the EITS web UI. Users opt in via Settings → General → Vim navigation. It provides:
- Prefix-based keybindings (`g`, `t`, `n`, `Space` leader)
- Which-key overlay that shows available next keys after a prefix
- Full help overlay (`?`)
- List navigation (`j`/`k`/`Enter`) on pages with `data-vim-list`
- Flyout focus mode (`F`) for the rail sidebar
- Command palette bridge (`Space f s`, `Space f r s`)

**This is NOT a standard Phoenix LiveView hook.** It mounts manually in `app.js` because Phoenix silently ignores `phx-hook` on root layout elements.

---

## File Map

| File | Lines | Role |
|------|-------|------|
| `assets/js/hooks/vim_nav.ts` | ~660 | Core VimNav object: key handling, overlays, scopes, actions |
| `assets/js/hooks/vim_nav_commands.ts` | ~300 | Command registry: all ~100 bindings, action types, PREFIXES set |
| `assets/js/hooks/vim_nav.test.ts` | ~1350 | 135 vitest tests -- must all pass before any commit |
| `assets/js/app.js` | -- | Manual VimNav mount via `phx:page-loading-stop` |
| `assets/js/hooks/command_palette.js` | -- | Command palette hook; handles `palette:open-command` event |
| `assets/js/hooks/palette_commands/sessions.js` | ~63 | `list-sessions` + `recent-sessions` palette commands |
| `assets/js/hooks/palette_commands/index.js` | ~18 | Aggregates all palette command modules |
| `lib/eye_in_the_sky_web/live/nav_hook.ex` | -- | Routes `palette:*` events to PaletteHandlers via attach_hook |
| `lib/eye_in_the_sky_web/live/nav_hook/palette_handlers.ex` | ~180 | Elixir handlers for palette events including `palette:recent-sessions` |
| `lib/eye_in_the_sky/sessions/queries.ex` | -- | `list_sessions_filtered/1`: `sort_by: :last_activity`, `limit:`, etc. |
| `lib/eye_in_the_sky_web/components/layouts/app.html.heex` | -- | `#vim-nav-root` element with `data-vim-nav-enabled` |
| `lib/eye_in_the_sky/settings.ex` | -- | Default: `"vim_nav_enabled" => "false"` |
| `docs/VIM_NAV.md` | -- | User-facing keybinding reference; rendered at `/keybindings` |
| `docs/VIM_NAV_LAZYVIM_PLAN.md` | -- | Planning doc for future phases |

---

## Architecture

### Mounting (app.js)

VimNav is NOT mounted via `phx-hook`. Phoenix ignores hooks on layout-level elements. Instead:

```js
let _vimNavInst = null
function _mountVimNav() {
  const el = document.getElementById("vim-nav-root")
  if (!el) return
  const enabled = el.dataset.vimNavEnabled === "true"
  if (_vimNavInst) {
    if (_vimNavInst._wasEnabled === enabled) return
    _vimNavInst.destroyed()
    _vimNavInst = null
  }
  if (!enabled) return
  const inst = Object.create(VimNav)
  inst.el = el
  inst._wasEnabled = enabled
  inst.pushEvent = (event, payload) => liveSocket.main?.pushHookEvent(el, el, event, payload)
  inst.pushEventToShell = (event, payload) => {
    const rail = document.getElementById("app-rail")
    if (rail) liveSocket.main?.pushHookEvent(rail, rail, event, payload)
  }
  inst.pushToList = (event, payload) => {
    const listEl = document.querySelector("[data-vim-list]")
    if (listEl) liveSocket.main?.pushHookEvent(listEl, listEl, event, payload)
  }
  inst.mounted()
  _vimNavInst = inst
}
window.addEventListener("phx:page-loading-stop", _mountVimNav)
```

Key points:
- `pushEvent` pushes to `#vim-nav-root` (NavHook territory)
- `pushEventToShell` pushes to `#app-rail` (shell LiveView)
- `pushToList` pushes to `[data-vim-list]` (active list view)
- `phx:page-loading-stop` fires on every LiveView navigation; this is how VimNav re-checks enabled state

### Command Registry (`vim_nav_commands.ts`)

Every keybinding is a `Command` object:

```ts
interface Command {
  id: string           // e.g. "leader.find.sessions"
  label: string        // e.g. "Find session"
  keys: string[]       // e.g. ["Space", "f", "s"]
  group: CommandGroup  // "navigation" | "toggle" | "create" | "global" | "context"
  action: CommandAction
  scope?: string       // optional -- see Scope System
}
```

Three action kinds:

```ts
// 1. Navigate -- window.location.assign
type NavigateAction = { kind: "navigate"; path: string; relative?: boolean }
// relative: true resolves against current project path prefix

// 2. Push event -- LiveView pushHookEvent
type PushEventAction = {
  kind: "push_event"
  event: string
  payload?: Record<string, unknown>
  target: "shell" | "active_view"  // shell = #app-rail, active_view = data-vim-list
  focus_flyout_after?: boolean      // enter flyout focus after event fires
}

// 3. Client -- handled in vim_nav.ts executeCommand()
type ClientAction = {
  kind: "client"
  name: "help" | "history_back" | "history_forward" | "command_palette" |
        "quick_create_note" | "quick_create_task" | "quick_create_chat" |
        "list_next" | "list_prev" | "list_open" | "page_search" |
        "list_archive" | "list_delete" | "list_yank_uuid" | "list_yank_id" |
        "focus_composer" | "focus_flyout" | "find_sessions" | "find_recent_sessions"
}
```

`PREFIXES: Set<string>` is exported -- all valid first keys of multi-key sequences. Used in `handleKey` to decide whether to start buffering.

### Scope System

`isCommandActive(cmd)` in `vim_nav.ts` evaluates scopes at runtime:

| Scope value | Active when |
|-------------|-------------|
| `undefined` or `"global"` | Always |
| `"feature:vim-list"` | `[data-vim-list]` exists OR flyout is open |
| `"feature:vim-flyout"` | `[data-vim-flyout-open="true"]` exists |
| `"feature:vim-search"` | `[data-vim-search]` exists |
| `"page:sessions"` | `[data-vim-page="sessions"]` exists |
| `"route_suffix:/X"` | `window.location.pathname` ends with `/X` or contains `/X/` |

### Key State in VimNav Object

```ts
buffer: string[]       // buffered prefix keys (e.g. ["Space", "g"])
mode: "normal"|"insert"
listFocusIndex: number // current j/k cursor in data-vim-list
flyoutFocused: boolean // F key entered flyout focus
helpOverlayEl: HTMLElement | null
whichKeyEl: HTMLElement | null
statusbarEl: HTMLElement   // "[ NORMAL ]" / "[ INSERT ]" fixed bottom-right
```

### Key Handling Flow

```
keydown event (capture phase, registered in mounted())
  |
  v
isEditableTarget(activeElement)? -> bail
  |
  v
mode == "insert"? -> check Escape -> switch to normal; else bail
  |
  v
Special intercepts: Escape (clear buffer, close overlays), ? (show help)
  |
  v
PREFIXES.has(key) or buffer.length > 0? -> buffer the key
  |
  v
Find matching COMMAND (full key sequence match)
  -> Found: executeCommand(cmd), clear buffer, hide which-key
  -> Not found but is prefix: showWhichKey(buffer)
  -> Not found, not prefix: if which-key showing -> hideWhichKey(); clear buffer
```

**Critical bug history:** `_onWhichKeyClose` was removed in the fix for Space g not rendering. It was a capture-phase listener on `document` that fired AFTER `_onKeydown` (registered earlier), cancelling the new which-key timer. Never re-add it.

### Which-Key Overlay

Rendered at bottom-left of viewport. Shows after any prefix key with a 0ms delay for Space or 300ms for others.

`showWhichKey(buffer)` calls `_renderWhichKey(buffer)`:
- Finds all COMMANDS where `keys[0..buffer.length-1]` matches current buffer
- Groups: sub-group header (e.g., `+go to page`) for commands 2+ keys away, direct label for 1 key away
- Switches to 2-column grid when > 8 entries

**Pressing `?` while which-key is open:** `handleKey` intercepts `?` before the prefix check when `buffer` is non-empty, calls `showHelp(buffer)` -- shows scoped sub-command help.

### Help Overlay (`?`)

`showHelp(prefix?: string[])`:
- `prefix` provided: shows only commands where `keys[0..prefix.length-1]` matches, displays relative remaining keys
- No prefix: shows all active commands grouped by section (Global, Go to page, Toggle rail, Create, Context); Space leader aliases excluded to avoid duplicates

Overlay is centered on screen (fixed, flex, items-center, justify-center), full-screen backdrop.

---

## DOM Marker Contract

VimNav reads these `data-*` attributes from templates. Never rename without updating `vim_nav.ts`.

| Attribute | Where | Effect |
|-----------|-------|--------|
| `data-vim-nav-enabled="true/false"` | `#vim-nav-root` in `app.html.heex` | Controls VimNav mount |
| `data-vim-list` | Sessions table, list containers | Enables j/k/Enter list nav; sets `pushToList` target |
| `data-vim-page="sessions"` | Sessions page container | Enables `page:sessions` scope (A/D/yu/yi) |
| `data-vim-search` | Search input wrapper | Enables `/` page search |
| `data-vim-list-item` | Individual list rows | j/k cursor management |
| `data-vim-flyout-open="true"` | Rail flyout root (when open) | Enables `feature:vim-flyout` scope |
| `data-vim-flyout-item` | Individual flyout items | Flyout j/k navigation |
| `data-vim-composer` | Chat composer (MISSING -- see Known Gaps) | `i` key focus target |

### CSS Styling

VimNav applies `vim-nav-focused` class to focused list/flyout items. Style with Tailwind:

```html
<div class="[&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50">
```

---

## Command Palette Bridge

The `find_sessions` and `find_recent_sessions` client actions dispatch a CustomEvent to `#command-palette`:

```ts
// In vim_nav.ts executeCommand():
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
```

`command_palette.js` handles `palette:open-command` in `mounted()`:
```js
this._openCommandHandler = (e) => this.openCommand(e.detail?.commandId)
this.el.addEventListener("palette:open-command", this._openCommandHandler)
```

### Recent Sessions Backend Flow

`palette:recent-sessions` uses a push_event flow (NOT sessionStorage):

1. `sessions.js` fires `hook.pushEvent("palette:recent-sessions", {})`
2. NavHook routes to `PaletteHandlers.handle_palette_event/3`
3. Handler calls `Sessions.list_sessions_filtered(status_filter: "all", sort_by: :last_activity, limit: 15)`
4. Pushes back `palette:recent-sessions-result` with session data
5. `command_palette.js` resolves `_paletteRecentSessionsResolve(sessions)`
6. Palette renders sessions sorted by last_activity_at

Result listener in `command_palette.js`:
```js
this.handleEvent("palette:recent-sessions-result", ({ sessions }) => {
  if (this._paletteRecentSessionsResolve) {
    this._paletteRecentSessionsResolve(sessions)
    this._paletteRecentSessionsResolve = null
  }
})
```

---

## Backend Wiring

### NavHook routing

Single `attach_hook` in `nav_hook.ex` routes all palette events:
```elixir
attach_hook(:palette_sessions, :handle_event, &PaletteHandlers.handle_palette_event/3)
```

Pattern matched in `palette_handlers.ex`:
- `"palette:sessions"` -- project-scoped session list
- `"palette:recent-sessions"` -- last-activity sorted, limit 15
- Fallback `_event` -- `{:cont, socket}`

### `list_sessions_filtered/1` opts

| Key | Values | Effect |
|-----|--------|--------|
| `sort_by:` | `:last_activity` (default), `:created`, `:name` | Sort order |
| `status_filter:` | `"all"`, `"active"` | Status filter |
| `limit:` | integer | Cap results |
| `project_id:` | integer | Filter by project |

---

## Complete Keybinding Table

### Base bindings (no prefix)

| Keys | Action | Scope |
|------|--------|-------|
| `?` | Help overlay | global |
| `:` | Command palette | global |
| `[` | History back | global |
| `]` | History forward | global |
| `q` | Close flyout | global |
| `/` | Focus search | feature:vim-search |
| `j` | Next list item | feature:vim-list |
| `k` | Previous list item | feature:vim-list |
| `Enter` | Open list item | feature:vim-list |
| `g g` | Jump to first item | feature:vim-list |
| `G` | Jump to last item | feature:vim-list |
| `F` | Focus flyout | feature:vim-flyout |
| `i` | Focus composer | route_suffix:/dm |
| `f f` | Toggle filter drawer | route_suffix:/tasks |
| `a d` | Toggle agent drawer | route_suffix:/chat |
| `m b` | Toggle members panel | route_suffix:/chat |
| `A` | Archive session | page:sessions |
| `D` | Delete session | page:sessions |
| `y u` | Copy UUID | page:sessions |
| `y i` | Copy int ID | page:sessions |

### `g` prefix -- Go to page

`g s/t/n/a/k/w/f/p/c/j/u/m/K/N/,/h` -- Sessions, Tasks, Notes, Agents, Kanban, Canvas, Files, Prompts, Chat, Jobs, Usage, Teams, Skills, Notifications, Settings, Keybindings

### `t` prefix -- Toggle rail section

Lowercase toggles open/close. Uppercase toggles and enters flyout focus.

`t s/t/n/f/w/c/k/m/j` -- toggle with focus available (`t S/T/N/F/W/C/K/M/J`)
`t a/u/b/P/p` -- toggle only (no focus variant)

### `n` prefix -- Create

`n a/t/n/c/p` -- Agent, Task, Note, Chat, Prompt
`n k` -- New Kanban Task (scope: route_suffix:/kanban)

### `Space` leader -- Phase A

| Keys | Action |
|------|--------|
| `Space e` | Toggle Files flyout |
| `Space q` | Close flyout |
| `Space :` | Command palette |
| `Space ?` | Keybinding help |
| `Space s s` | Focus search |
| `Space f s` | Find session (palette) |
| `Space f r s` | Find recent session (backend, sorted by last_activity_at) |
| `Space f t` | Find task (palette, project-scoped when project context available) |
| `Space b a` | Archive session (scope: page:sessions) |
| `Space b D` | Delete session (scope: page:sessions) |
| `Space x x` | Close all flyouts |
| `Space g *` | Go to page (aliases of g prefix) |
| `Space t *` | Toggle rail (aliases of t prefix) |
| `Space n *` | Create (aliases of n prefix) |

---

## How to Add a New Command

1. Add entry to `COMMANDS` in `vim_nav_commands.ts`
2. If new `client` action name: add to `ClientAction.name` union AND implement in `executeCommand()` in `vim_nav.ts`
3. If backend event needed: add handler in `palette_handlers.ex` and result listener in `command_palette.js`
4. Add tests in `vim_nav.test.ts`
5. Update `docs/VIM_NAV.md`
6. Run `mix compile --warnings-as-errors` before committing

---

## Running Tests

```bash
cd .claude/worktrees/<name>/assets
ln -sf ../../../../assets/node_modules node_modules
ln -sf ../../../../assets/vitest.config.mjs vitest.config.mjs
ln -sf ../../../../assets/package.json package.json
npx vitest run js/hooks/vim_nav.test.ts
```

All 135 tests must pass. Tests use jsdom, mock `window.location`, `localStorage`, `document`, and the LiveView socket API. No running server needed.

---

## Worktree Workflow

```bash
git worktree add .claude/worktrees/vim-nav-<feature> -b vim-nav-<feature>
cd .claude/worktrees/vim-nav-<feature>
ln -s ../../../deps deps
mix compile
```

Use `unlink deps` to remove symlinks. NEVER use `rm` on symlinks -- it is aliased to `rm-trash` and will trash the target.

**No PRs.** When the branch is ready, review the diff locally, then merge directly into main:

```bash
git diff main...<branch> --stat   # sanity check
git merge --no-ff <branch> -m "merge: <description>"
git worktree remove .claude/worktrees/<name>   # clean up after merge
```

---

## Known Gaps

### 1. ~~`data-vim-composer` not placed in any template~~ FIXED

`data-vim-composer` added to `lib/eye_in_the_sky_web/components/dm_page/composer.ex`. The `i` key works on DM pages.

### 2. ~~`docs/VIM_NAV.md` missing Space f entries~~ FIXED

`Space f t` added to docs in merge `vim-nav-ts-backend`. All Space f commands documented.

### 3. `data-vim-search` wiring -- partially complete

Added `vim_search={true}` prop to `search_bar` core component (renders as `data-vim-search`). Wired to tasks, teams, skills top bars. Pages still missing: workspace notes, prompts, kanban main search bar (uses a different search pattern than `search_bar` component).

---

## Anti-Patterns

**sessionStorage for recent sessions** -- LiveView SPA nav between DM pages does not reliably fire `phx:page-loading-stop`, so ring buffers go stale. Always use a backend push event for fresh data.

**Re-adding `_onWhichKeyClose`** -- Removed because it was a capture-phase listener that fired AFTER `_onKeydown`, cancelling the new which-key timer. The fix is in `handleKey`: unrecognized keys while which-key is showing call `hideWhichKey()` in the not-a-prefix branch.

**Wrong element in pushHookEvent** -- Second arg is the "owner" element. Always pass the same element twice:
```js
liveSocket.main?.pushHookEvent(el, el, event, payload)
```

**Space leader aliases without base bindings** -- Every `Space g X` mirrors a `g X`. Help overlay excludes Space aliases; the base binding must exist for it to appear in help.

---

## Settings Integration

VimNav enabled state is stored in the `settings` table. Default: `"vim_nav_enabled" => "false"`.

`data-vim-nav-enabled` on `#vim-nav-root` is set from this setting in the layout. VimNav re-checks on every `phx:page-loading-stop` -- settings changes take effect on next navigation without page reload.

---

## Key Timing

| Prefix | Which-key delay | Buffer window |
|--------|----------------|---------------|
| `Space` | 0ms | 2000ms |
| all others | 300ms | 1000ms |

Constants defined in `vim_nav.ts`. Space gets 0ms because it's the primary leader and should feel instant.

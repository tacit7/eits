# Command Palette — Linear-Style Redesign

**Date:** 2026-03-15
**Status:** Approved for implementation

The old draft `command-palette-linear-style-redesign.md` at the project root is superseded by this document.

---

## Overview

Redesign the existing navigation-only command palette into a full action palette modeled after Linear's: hierarchical submenus, action commands, fuzzy matching with character highlighting, and a clean UX that hides implementation details (no raw URLs).

---

## Keyboard Trigger

Platform-aware. On macOS, only Cmd+K opens the palette. On Windows/Linux, only Ctrl+K.

**Platform detection** — use `userAgentData` where available, fall back to `navigator.platform`:

```js
const isMac = navigator.userAgentData
  ? navigator.userAgentData.platform === "macOS"
  : navigator.platform.toUpperCase().includes("MAC")
```

**Focus guard** — always opens on Cmd/Ctrl+K, **except** when focus is inside a known rich editor container (CodeMirror, Monaco, contenteditable composer). Normal `<input>` and `<textarea>` elements do NOT block the shortcut.

```js
if ((isMac ? e.metaKey : e.ctrlKey) && e.key.toLowerCase() === "k") {
  const inEditor = document.activeElement?.closest(".cm-editor, .monaco-editor, [data-palette-no-intercept]")
  if (inEditor) return
  e.preventDefault()
  this.open()
}
```

The `GlobalKeydown` hook in the DM page uses `ctrlKey` for the task drawer. On macOS, Ctrl+K opens the drawer and Cmd+K opens the palette — no conflict.

---

## Command Model

Every entry in the palette is a flat discriminated union keyed on `type`. No nested `action` wrapper.

### Navigate

```js
{
  id: "go-sessions",
  label: "Sessions",
  icon: "hero-cpu-chip",
  group: "Workspace",
  hint: "Workspace",
  keywords: [],
  shortcut: null,
  type: "navigate",
  href: "/",
  when: null
}
```

### Callback

```js
{
  id: "toggle-theme",
  label: "Toggle Theme",
  icon: "hero-moon",
  group: "System",
  hint: null,
  keywords: ["dark", "light", "mode"],
  shortcut: null,
  type: "callback",
  fn: () => { /* see toggle-theme spec below */ },
  when: null
}
```

### Submenu

```js
{
  id: "go-project",
  label: "Go to Project...",
  icon: "hero-folder",
  group: "Projects",
  hint: null,
  keywords: ["open", "switch"],
  shortcut: null,
  type: "submenu",
  commands: () => collectProjectCommands(),   // array OR () => Command[]
  when: null
}
```

### Field Reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | yes | Unique across all commands |
| `label` | string | yes | Display text |
| `icon` | string | yes | `hero-`-prefixed Heroicon name only (e.g. `hero-plus`). No emoji. |
| `group` | string | yes | Category label |
| `hint` | string\|null | no | Subtitle below label. Explicit — never derived from href. |
| `keywords` | string[] | no | Extra search terms |
| `shortcut` | string\|null | no | Display-only. Rendered as `<kbd>` elements separated by spaces. |
| `type` | `"navigate"\|"callback"\|"submenu"` | yes | Discriminant |
| `href` | string | navigate only | Target path |
| `fn` | function | callback only | Called on activation. Palette closes after call. |
| `commands` | Command[]\|() => Command[] | submenu only | Resolved **lazily** — called when the submenu is pushed, not at palette open. |
| `when` | (() => boolean)\|null | no | If present and returns false, command is excluded entirely from `filteredItems()` and from recents display. Not CSS-hidden. Does not occupy an index. |

---

## State Machine

The palette maintains a **stack** of submenu contexts. Root is the implicit base.

### Stack Entry Shape

```js
{ id: string, label: string, commands: Command[] }
```

### Navigation Rules

| Action | Condition | Effect |
|--------|-----------|--------|
| Select `submenu` command | any depth | Resolve `commands` (call if function); push `{id, label, commands: resolved}` onto stack; clear query |
| Select `navigate` command | any depth | Save to recent; `window.location.assign(href)`; close palette |
| Select `callback` command | any depth | Call `fn()`; close palette |
| `Escape` | `stack.length > 0` | Pop stack; clear query |
| `Escape` | `stack.length === 0` | Close palette |
| `Backspace` | query empty + `stack.length > 0` + `e.isComposing === false` | Pop stack |
| `Enter` | item selected | Activate selected command (per type above) |
| `↓` | any | Move selection forward; wraps from last item to index 0 |
| `↑` | any | Move selection backward; wraps from index 0 to last item |

`Tab` to push submenu is **out of scope**.

**IME guard on Backspace:** Check `e.isComposing === true` and bail — never pop during CJK or accent composition.

### Breadcrumb

Element: `<div data-palette-breadcrumb>` — placed inside the `border-b` header div, **above** the `<input>`. Hidden (CSS `hidden` class or `display:none`) when `stack.length === 0`; not removed from DOM.

Format when visible: `Commands › {stack[0].label} › {stack[1].label} …`

---

## UX Behavior

### Filtering

- **No query, root:** Recent items first (up to 8, `navigate` type only — see Recent Items), then remaining commands grouped by `group` with group headers. Commands where `when()` returns false excluded.
- **No query, submenu:** All child commands as flat list. No group headers. Commands where `when()` returns false excluded.
- **With query, any depth:** Flat ranked list, no group headers, capped at 40. Commands where `when()` returns false excluded.
- **Empty results:** `<div class="px-3 py-4 text-sm text-base-content/50">No matches</div>`.

### Fuzzy Matching

Scoring applied to `label`, `keywords`, `hint`, and `group`. `href` is **not scored**.

| Match | Score |
|-------|-------|
| Exact label match (case-insensitive) | 200 |
| Label starts with query | 100 |
| Label contains query as substring | 50 |
| All query chars appear in label in order (fuzzy) | 60 + consecutive bonus |
| Any keyword contains query as substring | 30 |
| Hint contains query as substring | 15 |
| Group contains query as substring | 10 |

**Fuzzy match:** Every character in `q` must appear in `label` in left-to-right order. Each consecutive matching character pair adds +2 to the score.

**Tie-breaking:** Equal scores → `a.label.localeCompare(b.label)`.

### Match Highlighting — XSS-safe algorithm

Compute match positions on the **pre-escape** string. Then build the output by processing the label character by character: escape each character individually with `escapeHtml`, and wrap characters at matched positions with `<mark>`. This avoids the index-shift problem caused by HTML entity expansion.

```js
function highlightLabel(label, matchedPositions) {
  // matchedPositions: Set<number> of indices in the original label string
  return [...label].map((char, i) =>
    matchedPositions.has(i)
      ? `<mark>${escapeHtml(char)}</mark>`
      : escapeHtml(char)
  ).join("")
}
```

Highlighting applied to `label` only — never `hint`, `keywords`, or `group`.

### Result Rows

```
[ icon ]  Label (highlighted)           [shortcut kbd] [›]
          hint text
```

- **Icon:** `<span class="hero-{name} w-4 h-4 shrink-0">` — same inline heroicon pattern used elsewhere in the app.
- **Label:** Rendered with `<mark>` highlights.
- **Hint:** `text-xs text-base-content/45` — rendered only if `hint` is non-null.
- **Shortcut:** `<kbd>` per token split on space (e.g. `"C T"` → `<kbd>C</kbd><kbd>T</kbd>`), right-aligned, only if `shortcut` is non-null.
- **Chevron:** `<span class="hero-chevron-right w-3 h-3">`, right-aligned, only for `type: "submenu"`.

No raw hrefs rendered anywhere.

### Debounce

Removed. Filter runs synchronously on every keystroke.

---

## Recent Items

- Only `navigate` commands eligible.
- `localStorage` key: `"command_palette_recent"` (unchanged).
- Schema: `[{id, label, href, at}]` — `id` field added to prior `{label, href, at}` shape.
- Deduplication key: `href`.
- Max stored: 8.
- Commands with `when()` returning false are excluded from recents display even if stored.
- At root/no-query: recents rendered first, then remaining commands (excluding those in recents by href).

---

## Initial Command Set

### Navigation

| ID | Label | Icon | Hint | href |
|----|-------|------|------|------|
| `go-sessions` | Sessions | `hero-cpu-chip` | `Workspace` | `/` |
| `go-tasks` | Tasks | `hero-clipboard-document-list` | `Workspace` | `/tasks` |
| `go-notes` | Notes | `hero-document-text` | `Workspace` | `/notes` |
| `go-usage` | Usage | `hero-chart-bar` | `Insights` | `/usage` |
| `go-prompts` | Prompts | `hero-book-open` | `Knowledge` | `/prompts` |
| `go-skills` | Skills | `hero-bolt` | `Knowledge` | `/skills` |
| `go-notifications` | Notifications | `hero-bell` | `Knowledge` | `/notifications` |
| `go-jobs` | Jobs | `hero-cog-6-tooth` | `System` | `/jobs` |
| `go-settings` | Settings | `hero-adjustments-horizontal` | `System` | `/settings` |

### Actions

**`create-task`**
- Type: `callback`
- Icon: `hero-plus`, Group: `Tasks`
- `fn`: `() => window.location.assign("/tasks?intent=create")`
- The Tasks LiveView must handle `?intent=create` to open the create drawer on load. This is **in scope** for the implementation — it is not pre-existing.

**`toggle-theme`**
- Type: `callback`
- Icon: `hero-moon`, Group: `System`
- `fn`: Inline toggle — do not call through the `phx:set-theme` event (wrong target). Execute directly.
- **Canonical source of truth:** `data-theme` attribute on `<html>`. Fall back to `localStorage` only if the attribute is absent. "System" mode is out of scope — toggle only between `light` and `dark`.

```js
fn: () => {
  const current = document.documentElement.getAttribute("data-theme") || localStorage.getItem("theme") || "light"
  const next = current === "dark" ? "light" : "dark"
  localStorage.setItem("theme", next)
  document.documentElement.setAttribute("data-theme", next)
  document.querySelectorAll(".theme-controller").forEach(c => {
    if (c.type === "checkbox") c.checked = next === "dark"
  })
}
```

**`copy-url`**
- Type: `callback`
- Icon: `hero-link`, Group: `System`
- `fn`:

```js
fn: () => {
  navigator.clipboard.writeText(window.location.href)
    .then(() => {
      window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
        detail: { text: window.location.href, format: "text/plain" }
      }))
    })
    .catch(() => {
      window.dispatchEvent(new CustomEvent("phx:copy_to_clipboard", {
        detail: { text: "", format: "text/plain", error: true }
      }))
    })
}
```

Uses the existing `phx:copy_to_clipboard` event for both success and failure toasts. The handler in `app.js` must be updated to check for `detail.error` and show a failure message (e.g. "Failed to copy") instead of the success toast.

### Submenus

**`go-project` — Go to Project...**

- Icon: `hero-folder`, Group: `Projects`
- `commands`: function, resolved lazily when submenu is pushed:

```js
commands: () => {
  const registryHrefs = new Set(getCommands().map(c => c.href).filter(Boolean))
  return [...document.querySelectorAll("#app-sidebar a[href^='/projects/']")]
    .map(a => ({ label: (a.textContent || "").trim().replace(/\s+/g, " "), href: a.getAttribute("href") }))
    .filter(({ label, href }) => label && href && href !== "#" && !registryHrefs.has(href))
    .map(({ label, href }) => ({
      id: "go-project-" + href.replace(/[^a-z0-9]+/gi, "-").toLowerCase(),
      label,
      icon: "hero-folder",
      group: "Projects",
      hint: "Projects",
      keywords: [],
      shortcut: null,
      type: "navigate",
      href,
      when: null
    }))
}
```

Deduplication key: `href` against static registry only (`getCommands()`). **Do not call `commands()` inside `getCommands()` — submenu resolution is always lazy to avoid circular dependency.**

---

## Implementation Scope

### Files Changed

| File | Change |
|------|--------|
| `assets/js/app.js` | Rewrite `Hooks.CommandPalette`; add `CommandRegistry` module inline; update keyboard trigger |
| `lib/eye_in_the_sky_web_web/components/layouts/app.html.heex` | Add `[data-palette-breadcrumb]` element; update footer copy |
| Tasks LiveView | Handle `?intent=create` param to open create drawer on mount |

### Footer Copy

```
↑↓ to move · Enter to select · Esc to close/back · Backspace to go back
```

### Out of Scope

- `Tab` to push submenu
- Context-aware commands (page-specific injection — future)
- Server-rendered command lists
- Persisting custom command bindings
- Mobile sub-palette UX changes

---

## Architecture Notes

**`CommandRegistry`** (inline in `app.js`, before `Hooks.CommandPalette`):
- `getCommands()` returns the static command array
- `when()` gates evaluated in `filteredItems()` — false → excluded before index assignment and before recents display
- Submenu `commands` functions are called lazily at push time, not at `open()`

**`Hooks.CommandPalette`:**
- `this.stack = []`
- `this.activeCommands()` → `stack.length ? stack[stack.length - 1].commands : getCommands()`
- `this.filteredItems()` → apply `when()`, then fuzzy score, then slice to 40
- `this.render()` → innerHTML with highlight markup and sequential `data-index`
- `this.activate(cmd)` → dispatch by `cmd.type`
- `this.open()` → reset `stack`, clear query, focus input, render
- `this.breadcrumb` → `this.el.querySelector("[data-palette-breadcrumb]")`

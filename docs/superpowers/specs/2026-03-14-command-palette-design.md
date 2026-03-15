# Command Palette — Linear-style Redesign

**Date:** 2026-03-14
**Status:** Approved, pending implementation

---

## Overview

Rewrite the `CommandPalette` hook in `assets/js/app.js` to act like Linear's command palette: hierarchical sub-menus, action commands (not just navigation), fuzzy match highlighting, icons per item, no visible URLs, and instant filtering.

---

## Item Shape

Every palette item uses an explicit `type` field. No magical union-by-presence-of-fields.

```js
{
  id: string,          // stable, never derived from label
  label: string,
  icon: string,        // heroicon name or emoji
  group: string,
  shortcut: string,    // display-only metadata; not a live keybinding unless explicitly wired
  type: "link" | "action" | "submenu",
  href: string,        // type: "link" only
  action: () => void,  // type: "action" only
  children: Item[],    // type: "submenu" only
}
```

**Why explicit `type`:** `href | action | children?` creates rendering and selection ambiguity. `submenu` is a distinct behavior, not just "an item with children."

---

## State Model

```
baseCommandRegistry       — static array, never mutated after definition
getDynamicProjectItems()  — DOM adapter; scrapes sidebar project links at open time
buildRootItems()          — composes session root: [...baseRegistry, ...getDynamicProjectItems()]
modeStack                 — ModeEntry[]
query                     — string, per-level, cleared on mode push
```

### ModeEntry shape

```js
{
  id: string,
  label: string,
  items: Item[],
  parentItemId: string | null,
  source: "root" | "submenu",
}
```

**Separation rationale:** `baseCommandRegistry` is never polluted with DOM-scraped items. `getDynamicProjectItems()` is explicitly an adapter — fragile by nature, isolated by design. If project data becomes available in JS state, replace the adapter without touching the registry.

---

## Selection Logic

One function handles all selection behavior:

```js
function executeCommand(item) {
  switch (item.type) {
    case "link":    navigate(item.href); break;
    case "action":  item.action(); break;
    case "submenu": pushMode(item); break;
  }
}
```

This function is the single entry point for both keyboard Enter and mouse click. No selection logic is smeared across event handlers.

---

## Mode Stack Navigation

| Action | Behavior |
|--------|----------|
| Select `submenu` item | `pushMode(item)` — new ModeEntry pushed, query cleared |
| Escape (depth > 1) | `popMode()` — return to parent mode |
| Escape (depth == 1) | Close palette |
| Backspace on empty input | `popMode()` if depth > 1 |

Filtering applies only to `currentMode().items` — never the full tree.

---

## Breadcrumb

When `modeStack.length > 1`, a breadcrumb renders below the input showing the navigation path:

```
Root > Change Theme
```

Hidden at root level.

---

## Fuzzy Match & Highlighting

- No debounce — filtering is synchronous and instant
- Scoring: exact match > prefix > substring > group match
- `highlightMatches(label, query)` wraps matching characters in `<mark>` tags
- Match is character-by-character fuzzy (not substring-only)

---

## Visual Row Layout

```
[icon]  Label with <mark>matched</mark> chars          [shortcut hint]
```

- No visible `href` displayed
- `shortcut` shown right-aligned as display-only metadata
- Active row highlighted with `bg-base-200`

---

## Initial Registry

| Group | ID | Type | Target |
|-------|----|------|--------|
| Navigate | `nav-sessions` | link | `/` |
| Navigate | `nav-tasks` | link | `/tasks` |
| Navigate | `nav-notes` | link | `/notes` |
| Navigate | `nav-usage` | link | `/usage` |
| Navigate | `nav-prompts` | link | `/prompts` |
| Navigate | `nav-skills` | link | `/skills` |
| Navigate | `nav-settings` | link | `/settings` |
| Navigate | `nav-jobs` | link | `/jobs` |
| Navigate | `nav-notifications` | link | `/notifications` |
| Actions | `action-create-task` | link | `/tasks?intent=create` |
| Preferences | `pref-theme` | submenu | children: Light / Dark / System |
| Projects | (dynamic) | link | scraped from sidebar |

### Intent navigation

"Create Task" navigates to `/tasks?intent=create`. The tasks page is responsible for detecting `?intent=create` and auto-opening the create drawer. Query param is the contract — no psychic inference.

---

## Shortcut Display vs Handling

`shortcut` on an item is **display-only metadata** — it renders in the row UI as a hint. It does not register a global key handler. If a real keybinding is needed, it must be explicitly wired in `bindPaletteEvents()` separately from the `shortcut` field. No decorative-text shortcut system.

---

## Logical Splits in `app.js`

The rewrite stays in one file but is organized into named functions:

```
baseCommandRegistry        — static data
getDynamicProjectItems()   — DOM adapter
buildRootItems()           — session root composition
createPaletteState()       — initial state factory
getCurrentMode()           — top of modeStack
filterItems(items, query)  — fuzzy filter
highlightMatches(label, q) — mark wrapper
executeCommand(item)       — single selection entry point
pushMode(item)             — stack push
popMode()                  — stack pop
renderPalette(state)       — DOM render
bindPaletteEvents()        — keyboard + mouse wiring
```

---

## Terminology

| Term | Meaning |
|------|---------|
| Command palette | The UI component |
| Palette item registry | `baseCommandRegistry` — the data model backing the palette |
| Mode stack | Navigation state within the palette |

---

## What Is Not Changing

- The `<dialog id="command-palette">` element in `app.html.heex` stays
- Cmd/Ctrl+K trigger stays
- `localStorage` recent items stay (scoped to root mode only)
- The `GlobalKeydown` hook in DM page stays — it handles its own Ctrl+K separately

---

## Out of Scope

- Per-level query restore on `popMode()`
- `emptyMessage` per mode
- Active live keybindings from palette item `shortcut` field
- Replacing DOM scraping with a JS-accessible project data source (deferred)

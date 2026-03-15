# Command Palette Linear-style Redesign — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing `CommandPalette` hook with a Linear-style palette that supports hierarchical sub-menus, action commands, fuzzy match highlighting, icons, and instant filtering.

**Architecture:** Extract the palette into `assets/js/hooks/command_palette.js` (following the existing hooks pattern), wire it in `app.js`, and add `?intent=create` support to the tasks LiveView. All state lives in a JS closure; no server round-trips for filtering.

**Tech Stack:** Vanilla JS, Phoenix LiveView hooks, Tailwind/DaisyUI, Elixir/Phoenix LiveView

**Spec:** `docs/superpowers/specs/2026-03-14-command-palette-design.md`

---

## Chunk 1: Registry, State, Filtering

### Task 1: Create `command_palette.js` with item registry and state model

**Files:**
- Create: `assets/js/hooks/command_palette.js`

- [ ] **Step 1: Create the file with the base command registry**

```js
// assets/js/hooks/command_palette.js

const baseCommandRegistry = [
  // Navigate
  { id: "nav-sessions",      label: "Sessions",      icon: "🖥️",  group: "Navigate",    type: "link", href: "/",              shortcut: "" },
  { id: "nav-tasks",         label: "Tasks",         icon: "✅",  group: "Navigate",    type: "link", href: "/tasks",          shortcut: "" },
  { id: "nav-notes",         label: "Notes",         icon: "📝",  group: "Navigate",    type: "link", href: "/notes",          shortcut: "" },
  { id: "nav-usage",         label: "Usage",         icon: "📊",  group: "Navigate",    type: "link", href: "/usage",          shortcut: "" },
  { id: "nav-prompts",       label: "Prompts",       icon: "💬",  group: "Navigate",    type: "link", href: "/prompts",        shortcut: "" },
  { id: "nav-skills",        label: "Skills",        icon: "⚡",  group: "Navigate",    type: "link", href: "/skills",         shortcut: "" },
  { id: "nav-settings",      label: "Settings",      icon: "⚙️",  group: "Navigate",    type: "link", href: "/settings",       shortcut: "" },
  { id: "nav-jobs",          label: "Jobs",          icon: "🔧",  group: "Navigate",    type: "link", href: "/jobs",           shortcut: "" },
  { id: "nav-notifications", label: "Notifications", icon: "🔔",  group: "Navigate",    type: "link", href: "/notifications",  shortcut: "" },
  // Actions
  {
    id: "action-create-task",
    label: "Create Task",
    icon: "➕",
    group: "Actions",
    type: "link",
    href: "/tasks?intent=create",
    shortcut: "C",
  },
  // Preferences
  {
    id: "pref-theme",
    label: "Change Theme",
    icon: "🎨",
    group: "Preferences",
    type: "submenu",
    shortcut: "",
    children: [
      { id: "pref-theme-light",  label: "Light",  icon: "☀️",  group: "Theme", type: "action", shortcut: "", action: () => setTheme("light") },
      { id: "pref-theme-dark",   label: "Dark",   icon: "🌙",  group: "Theme", type: "action", shortcut: "", action: () => setTheme("dark") },
      { id: "pref-theme-system", label: "System", icon: "💻",  group: "Theme", type: "action", shortcut: "", action: () => setTheme("system") },
    ],
  },
]

function setTheme(value) {
  if (value === "system") {
    localStorage.removeItem("theme")
    document.documentElement.removeAttribute("data-theme")
  } else {
    localStorage.setItem("theme", value)
    document.documentElement.setAttribute("data-theme", value)
  }
}
```

- [ ] **Step 2: Add the DOM adapter for dynamic project items**

Append to `command_palette.js`:

```js
function getDynamicProjectItems() {
  return [...document.querySelectorAll("#app-sidebar a[href]")]
    .map((a) => ({
      label: (a.textContent || "").trim().replace(/\s+/g, " "),
      href: a.getAttribute("href"),
    }))
    .filter((item) => item.label && item.href && item.href.startsWith("/projects/"))
    .map((item) => ({
      id: `dynamic-project-${item.href}`,
      label: item.label,
      icon: "📁",
      group: "Projects",
      type: "link",
      href: item.href,
      shortcut: "",
    }))
}

function buildRootItems() {
  const dynamic = getDynamicProjectItems()
  const seen = new Set(baseCommandRegistry.map((i) => i.id))
  const deduped = dynamic.filter((i) => !seen.has(i.id))
  return [...baseCommandRegistry, ...deduped]
}
```

- [ ] **Step 3: Add state factory and mode stack helpers**

Append to `command_palette.js`:

```js
function createPaletteState() {
  return {
    modeStack: [],
    query: "",
    activeIndex: 0,
  }
}

function getCurrentMode(state) {
  return state.modeStack[state.modeStack.length - 1]
}

function pushMode(state, item) {
  state.modeStack.push({
    id: `mode-${item.id}`,
    label: item.label,
    items: item.children,
    parentItemId: item.id,
    source: "submenu",
  })
  state.query = ""
  state.activeIndex = 0
}

function popMode(state) {
  if (state.modeStack.length > 1) {
    state.modeStack.pop()
    state.query = ""
    state.activeIndex = 0
    return true
  }
  return false
}
```

- [ ] **Step 4: Verify file is syntactically valid**

```bash
node --input-type=module < assets/js/hooks/command_palette.js 2>&1 | head -5
```

Expected: no syntax errors (undefined reference errors are fine at this stage)

- [ ] **Step 5: Commit**

```bash
git add assets/js/hooks/command_palette.js
git commit -m "feat(palette): add palette item registry and state model"
```

---

### Task 2: Add fuzzy filtering and match highlighting

**Files:**
- Modify: `assets/js/hooks/command_palette.js`

- [ ] **Step 1: Add `escapeHtml` helper and `fuzzyScore`**

Append to `command_palette.js`:

```js
function escapeHtml(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
}

function fuzzyScore(text, query) {
  const t = text.toLowerCase()
  const q = query.toLowerCase()
  if (t === q) return 200
  if (t.startsWith(q)) return 150
  let score = t.includes(q) ? 80 : 0
  let tIdx = 0, qIdx = 0, consecutive = 0
  while (tIdx < t.length && qIdx < q.length) {
    if (t[tIdx] === q[qIdx]) {
      score += 10 + consecutive * 5
      consecutive++
      qIdx++
    } else {
      consecutive = 0
    }
    tIdx++
  }
  if (qIdx < q.length) return 0 // not all query chars found in order
  return score
}
```

- [ ] **Step 2: Add `filterItems` and `highlightMatches`**

Append to `command_palette.js`:

```js
function filterItems(items, query) {
  if (!query) return items
  return items
    .map((item) => ({
      ...item,
      _score: fuzzyScore(item.label, query) + fuzzyScore(item.group || "", query) * 0.3,
    }))
    .filter((item) => item._score > 0)
    .sort((a, b) => b._score - a._score)
}

function highlightMatches(label, query) {
  if (!query) return escapeHtml(label)
  const q = query.toLowerCase()
  const l = label.toLowerCase()
  let result = ""
  let qIdx = 0
  for (let i = 0; i < label.length; i++) {
    if (qIdx < q.length && l[i] === q[qIdx]) {
      result += `<mark class="bg-primary/20 text-primary rounded-sm">${escapeHtml(label[i])}</mark>`
      qIdx++
    } else {
      result += escapeHtml(label[i])
    }
  }
  return result
}
```

- [ ] **Step 3: Commit**

```bash
git add assets/js/hooks/command_palette.js
git commit -m "feat(palette): add fuzzy filtering and match highlighting"
```

---

## Chunk 2: Rendering, Events, and Hook Export

### Task 3: Add render function

**Files:**
- Modify: `assets/js/hooks/command_palette.js`

- [ ] **Step 1: Add `renderPalette`**

Append to `command_palette.js`:

```js
function renderPalette(state, el) {
  const results = el.querySelector("[data-palette-results]")
  const breadcrumb = el.querySelector("[data-palette-breadcrumb]")
  if (!results) return

  const mode = getCurrentMode(state)
  const items = filterItems(mode.items, state.query)
  state.activeIndex = Math.min(state.activeIndex, Math.max(items.length - 1, 0))

  // Breadcrumb
  if (breadcrumb) {
    if (state.modeStack.length > 1) {
      breadcrumb.textContent = state.modeStack.map((m) => m.label).join(" › ")
      breadcrumb.classList.remove("hidden")
    } else {
      breadcrumb.classList.add("hidden")
    }
  }

  if (items.length === 0) {
    results.innerHTML = `<div class="px-3 py-4 text-sm text-base-content/50">No matches</div>`
    return
  }

  // Group items preserving order
  const groups = new Map()
  for (const item of items) {
    if (!groups.has(item.group)) groups.set(item.group, [])
    groups.get(item.group).push(item)
  }

  let idx = 0
  results.innerHTML = [...groups.entries()].map(([group, groupItems]) => {
    const buttons = groupItems.map((item) => {
      const i = idx++
      const isActive = i === state.activeIndex
      const highlighted = highlightMatches(item.label, state.query)
      const chevron = item.type === "submenu"
        ? ` <span class="text-base-content/40 text-xs">›</span>`
        : ""
      const shortcutHint = item.shortcut
        ? `<kbd class="ml-auto text-[10px] px-1.5 py-0.5 rounded bg-base-300 text-base-content/50 font-mono flex-shrink-0">${escapeHtml(item.shortcut)}</kbd>`
        : ""
      return `
        <button
          type="button"
          data-palette-index="${i}"
          role="option"
          aria-selected="${isActive}"
          class="w-full text-left flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm transition-colors ${isActive ? "bg-base-200 text-base-content" : "hover:bg-base-200/60 text-base-content/80"}"
        >
          <span class="text-base leading-none flex-shrink-0">${escapeHtml(item.icon || "")}</span>
          <span class="flex-1 font-medium truncate">${highlighted}${chevron}</span>
          ${shortcutHint}
        </button>`
    }).join("")

    return `
      <section class="px-1 py-1">
        <h3 class="px-2 py-1 text-[10px] uppercase tracking-wider text-base-content/40">${escapeHtml(group)}</h3>
        ${buttons}
      </section>`
  }).join("")

  const activeEl = results.querySelector(`[data-palette-index="${state.activeIndex}"]`)
  if (activeEl) activeEl.scrollIntoView({ block: "nearest" })
}
```

- [ ] **Step 2: Commit**

```bash
git add assets/js/hooks/command_palette.js
git commit -m "feat(palette): add renderPalette with grouped results and breadcrumb"
```

---

### Task 4: Add recent items helpers and export the hook

**Files:**
- Modify: `assets/js/hooks/command_palette.js`

- [ ] **Step 1: Add recent items helpers**

Append to `command_palette.js`:

```js
function loadRecent() {
  try {
    const parsed = JSON.parse(localStorage.getItem("command_palette_recent") || "[]")
    return Array.isArray(parsed) ? parsed : []
  } catch (_) {
    return []
  }
}

function saveRecent(item) {
  const existing = loadRecent().filter((e) => e.id !== item.id)
  const next = [{ id: item.id, label: item.label, href: item.href }, ...existing].slice(0, 8)
  localStorage.setItem("command_palette_recent", JSON.stringify(next))
}

function applyRecentOrdering(items) {
  const recent = loadRecent()
  const recentIds = recent.map((r) => r.id)
  const recentItems = recentIds.map((id) => items.find((i) => i.id === id)).filter(Boolean)
  const recentSet = new Set(recentIds)
  const rest = items.filter((i) => !recentSet.has(i.id))
  return [...recentItems, ...rest]
}
```

- [ ] **Step 2: Add `executeCommand` and export the hook**

Append to `command_palette.js`:

```js
function executeCommand(item, closeFn) {
  switch (item.type) {
    case "link":
      saveRecent(item)
      window.location.assign(item.href)
      break
    case "action":
      closeFn()
      item.action()
      break
    // "submenu" is handled by caller via pushMode — never reaches here
  }
}

export const CommandPalette = {
  mounted() {
    this._state = createPaletteState()

    this._openHandler = () => this._open()
    this.el.addEventListener("palette:open", this._openHandler)

    this._globalKeyHandler = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        this._open()
      }
    }
    window.addEventListener("keydown", this._globalKeyHandler)

    const input = this.el.querySelector("[data-palette-input]")
    input?.addEventListener("input", (e) => {
      this._state.query = e.target.value
      this._state.activeIndex = 0
      renderPalette(this._state, this.el)
    })
    input?.addEventListener("keydown", (e) => this._onKeydown(e))

    this.el.querySelector("[data-palette-results]")?.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-palette-index]")
      if (!btn) return
      const idx = Number(btn.dataset.paletteIndex)
      const mode = getCurrentMode(this._state)
      const items = filterItems(mode.items, this._state.query)
      const item = items[idx]
      if (item) this._select(item)
    })
  },

  destroyed() {
    window.removeEventListener("keydown", this._globalKeyHandler)
    this.el.removeEventListener("palette:open", this._openHandler)
  },

  _open() {
    this._state = createPaletteState()
    this._state.modeStack = [{
      id: "root",
      label: "Root",
      items: applyRecentOrdering(buildRootItems()),
      parentItemId: null,
      source: "root",
    }]
    this.el.showModal()
    const input = this.el.querySelector("[data-palette-input]")
    if (input) { input.value = ""; input.focus() }
    renderPalette(this._state, this.el)
  },

  _select(item) {
    if (item.type === "submenu") {
      pushMode(this._state, item)
      const input = this.el.querySelector("[data-palette-input]")
      if (input) input.value = ""
      renderPalette(this._state, this.el)
    } else {
      executeCommand(item, () => this.el.close())
    }
  },

  _onKeydown(e) {
    const mode = getCurrentMode(this._state)
    const items = filterItems(mode.items, this._state.query)

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this._state.activeIndex = Math.min(this._state.activeIndex + 1, items.length - 1)
      renderPalette(this._state, this.el)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this._state.activeIndex = Math.max(this._state.activeIndex - 1, 0)
      renderPalette(this._state, this.el)
    } else if (e.key === "Enter") {
      e.preventDefault()
      const item = items[this._state.activeIndex]
      if (item) this._select(item)
    } else if (e.key === "Escape") {
      e.preventDefault()
      if (!popMode(this._state)) {
        this.el.close()
      } else {
        const input = this.el.querySelector("[data-palette-input]")
        if (input) input.value = ""
        renderPalette(this._state, this.el)
      }
    } else if (e.key === "Backspace" && !this._state.query) {
      if (popMode(this._state)) {
        const input = this.el.querySelector("[data-palette-input]")
        if (input) input.value = ""
        renderPalette(this._state, this.el)
      }
    }
  },
}
```

- [ ] **Step 3: Commit**

```bash
git add assets/js/hooks/command_palette.js
git commit -m "feat(palette): add recent items, executeCommand, and export hook"
```

---

## Chunk 3: HTML Update, app.js Wiring, Intent Navigation

### Task 5: Update `app.html.heex` to add breadcrumb element

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/layouts/app.html.heex`

- [ ] **Step 1: Update the command palette dialog input wrapper**

Find in `app.html.heex`:

```heex
<div class="border-b border-base-content/10 p-3">
  <label for="command-palette-input" class="sr-only">Search commands</label>
  <input
    id="command-palette-input"
    type="text"
    data-palette-input
    placeholder="Search pages, projects, and commands..."
    class="w-full h-10 rounded-lg border border-base-content/10 bg-base-100 px-3 text-sm focus:outline-none focus:border-primary/40"
  />
</div>
```

Replace with:

```heex
<div class="border-b border-base-content/10 p-3 space-y-1.5">
  <label for="command-palette-input" class="sr-only">Search commands</label>
  <input
    id="command-palette-input"
    type="text"
    data-palette-input
    placeholder="Search..."
    class="w-full h-10 rounded-lg border border-base-content/10 bg-base-100 px-3 text-sm focus:outline-none focus:border-primary/40"
  />
  <div data-palette-breadcrumb class="hidden text-[11px] text-base-content/50 px-1 font-mono"></div>
</div>
```

- [ ] **Step 2: Verify compile**

```bash
mix compile
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/layouts/app.html.heex
git commit -m "feat(palette): add breadcrumb slot to command palette dialog"
```

---

### Task 6: Wire `CommandPalette` into `app.js`, remove old hook

**Files:**
- Modify: `assets/js/app.js`

- [ ] **Step 1: Find the old hook block boundaries**

```bash
grep -n "Hooks.CommandPalette" assets/js/app.js
```

Expected output: two lines — one where `Hooks.CommandPalette = {` starts and one where it ends (the closing `}`). Note both line numbers.

- [ ] **Step 2: Add import near the top of `app.js`** (with the other hook imports, around line 26-40)

```js
import {CommandPalette} from "./hooks/command_palette"
```

- [ ] **Step 3: Register the hook** (near the other `Hooks.X = X` lines)

```js
Hooks.CommandPalette = CommandPalette
```

- [ ] **Step 4: Delete the old `Hooks.CommandPalette = { ... }` block from `app.js`**

Using the line numbers from Step 1, delete the entire old block from `Hooks.CommandPalette = {` through its closing `}`. Do not leave a stub or comment.

- [ ] **Step 5: Verify build**

```bash
mix compile
```

Expected: no errors

- [ ] **Step 6: Commit**

```bash
git add assets/js/app.js
git commit -m "feat(palette): replace inline CommandPalette with extracted hook"
```

---

### Task 7: Add create task drawer to `OverviewLive.Tasks`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/tasks.ex`

The overview tasks page has no create task capability at all. This task adds it fully: assigns, event handlers, and the drawer component.

- [ ] **Step 1: Add assigns to `mount/3`**

In the `mount/3` assign chain, add:

```elixir
|> assign(:show_new_task_drawer, false)
```

- [ ] **Step 2: Add `toggle_new_task_drawer` event handler**

After the existing `handle_event` clauses:

```elixir
@impl true
def handle_event("toggle_new_task_drawer", _params, socket) do
  {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
end
```

- [ ] **Step 3: Add `create_new_task` event handler**

```elixir
@impl true
def handle_event("create_new_task", params, socket) do
  title = params["title"]
  description = params["description"]
  state_id = parse_int(params["state_id"], 0)
  priority = parse_int(params["priority"], 1)
  tags_string = params["tags"] || ""

  tag_names =
    tags_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  task_uuid = String.upcase(Ecto.UUID.generate())
  now = DateTime.utc_now() |> DateTime.to_iso8601()

  case Tasks.create_task(%{
         uuid: task_uuid,
         title: title,
         description: description,
         state_id: state_id,
         priority: priority,
         project_id: nil,
         created_at: now,
         updated_at: now
       }) do
    {:ok, task} ->
      Tasks.replace_task_tags(task.id, tag_names)

      {:noreply,
       socket
       |> assign(:show_new_task_drawer, false)
       |> load_tasks()
       |> put_flash(:info, "Task created successfully")}

    {:error, changeset} ->
      {:noreply,
       put_flash(socket, :error, "Failed to create task: #{inspect(changeset.errors)}")}
  end
end
```

Note: `parse_int/2` is already imported via `EyeInTheSkyWebWeb.Live.Shared.TasksHelpers` — no new import needed.

- [ ] **Step 4: Add `handle_params/3` for `?intent=create`**

After `mount/3`:

```elixir
@impl true
def handle_params(%{"intent" => "create"} = _params, _uri, socket) do
  {:noreply, assign(socket, :show_new_task_drawer, true)}
end

def handle_params(_params, _uri, socket) do
  {:noreply, socket}
end
```

- [ ] **Step 5: Add `NewTaskDrawer` component to the template**

In the `render/1` function, just before the existing `<!-- Task Detail Drawer -->` block (line ~277), insert:

```heex
<!-- New Task Drawer -->
<.live_component
  module={EyeInTheSkyWebWeb.Components.NewTaskDrawer}
  id="overview-new-task-drawer"
  show={@show_new_task_drawer}
  workflow_states={@workflow_states}
  toggle_event="toggle_new_task_drawer"
  submit_event="create_new_task"
/>
```

`NewTaskDrawer` requires: `id`, `show`, `workflow_states`, `toggle_event`, `submit_event`. No `project_id` — the component does not use one.

- [ ] **Step 6: Verify compile**

```bash
mix compile
```

Expected: no errors

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/tasks.ex
git commit -m "feat(tasks): add create task drawer and handle ?intent=create"
```

---

## Chunk 4: Smoke Test

### Task 8: Manual browser verification

- [ ] Start the server: `mix phx.server`
- [ ] Press Cmd+K — palette opens, items show icons, no raw URLs
- [ ] Type "ses" — "Sessions" highlights matching chars instantly
- [ ] Arrow keys move active highlight; Enter navigates
- [ ] Type "theme", Enter on "Change Theme" — sub-palette opens, breadcrumb shows `Root › Change Theme`
- [ ] Escape from sub-palette — returns to root (does not close)
- [ ] Escape from root — closes palette
- [ ] Backspace on empty input in sub-palette — returns to root
- [ ] Navigate to `/tasks?intent=create` — create drawer opens automatically
- [ ] Select an item, re-open palette — that item appears at top of list
- [ ] Open palette > Change Theme > Dark — theme switches without page reload
- [ ] `mix compile` — no errors

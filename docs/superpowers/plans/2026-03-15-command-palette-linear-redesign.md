# Command Palette Linear-Style Redesign — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the navigation-only command palette with a Linear-style action palette featuring hierarchical submenus, fuzzy matching, match highlighting, and action commands.

**Architecture:** `CommandRegistry` module (inline in `app.js`) holds all commands as a flat discriminated union. `Hooks.CommandPalette` rewrites the Phoenix hook to maintain a navigation stack and render results with highlight markup. HTML template adds a breadcrumb element. Tasks LiveView gains `?intent=create` handling that opens the `NewTaskDrawer` component.

**Tech Stack:** Phoenix LiveView, Vanilla JS (no new dependencies), DaisyUI/Tailwind, Heroicons.

---

## Chunk 1: Infrastructure — `phx:copy_to_clipboard` error support + HTML template

## Chunk 2: CommandRegistry + keyboard trigger

## Chunk 3: Hooks.CommandPalette rewrite

## Chunk 4: Tasks LiveView — `?intent=create`

---

## Chunk 1: Infrastructure

### Task 1: Update `phx:copy_to_clipboard` handler to support failure toasts

**Files:**
- Modify: `assets/js/app.js` (the `phx:copy_to_clipboard` event listener near bottom of file)

- [ ] **Step 1: Open `assets/js/app.js` and locate the `phx:copy_to_clipboard` handler (~line 863)**

  Current code:
  ```js
  window.addEventListener("phx:copy_to_clipboard", (e) => {
    const { text, format } = e.detail
    if (!text || !navigator.clipboard) return

    navigator.clipboard.writeText(text).then(() => {
      const toast = document.createElement("div")
      toast.className = "fixed bottom-4 right-4 z-[9999] bg-base-content text-base-100 text-xs font-medium px-4 py-2 rounded-lg shadow-lg opacity-0 transition-opacity duration-200"
      toast.textContent = `Copied as ${format}`
      document.body.appendChild(toast)
      requestAnimationFrame(() => { toast.style.opacity = "1" })
      setTimeout(() => {
        toast.style.opacity = "0"
        setTimeout(() => toast.remove(), 200)
      }, 2000)
    }).catch(err => console.error("Failed to copy:", err))
  })
  ```

- [ ] **Step 2: Replace it with the version that handles `detail.error`**

  ```js
  function showToast(message) {
    const toast = document.createElement("div")
    toast.className = "fixed bottom-4 right-4 z-[9999] bg-base-content text-base-100 text-xs font-medium px-4 py-2 rounded-lg shadow-lg opacity-0 transition-opacity duration-200"
    toast.textContent = message
    document.body.appendChild(toast)
    requestAnimationFrame(() => { toast.style.opacity = "1" })
    setTimeout(() => {
      toast.style.opacity = "0"
      setTimeout(() => toast.remove(), 200)
    }, 2000)
  }

  window.addEventListener("phx:copy_to_clipboard", (e) => {
    const { text, format, error } = e.detail

    if (error) {
      showToast("Failed to copy")
      return
    }

    if (!text || !navigator.clipboard) return

    navigator.clipboard.writeText(text).then(() => {
      showToast(`Copied as ${format}`)
    }).catch(err => {
      console.error("Failed to copy:", err)
      showToast("Failed to copy")
    })
  })
  ```

  Place `showToast` as a module-level function before the event listener.

- [ ] **Step 3: Verify `mix compile` passes**

  Run: `cd /Users/urielmaldonado/projects/eits/web && mix compile`
  Expected: No errors (only warnings acceptable)

- [ ] **Step 4: Commit**

  ```bash
  git add assets/js/app.js
  git commit -m "feat(palette): add error toast support to phx:copy_to_clipboard handler"
  ```

---

### Task 2: Update HTML template — breadcrumb + footer copy

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/layouts/app.html.heex`

- [ ] **Step 1: Locate the `#command-palette` dialog (~line 137)**

  The dialog's inner structure:
  ```html
  <div class="modal-box max-w-2xl p-0 overflow-hidden">
    <div class="border-b border-base-content/10 p-3">
      <label for="command-palette-input" class="sr-only">Search commands</label>
      <input ... />
    </div>
    <div data-palette-results ...></div>
    <div class="px-3 py-2 text-[11px] ...">
      Arrow keys to move • Enter to navigate • Esc to close • Cmd/Ctrl+K to open
    </div>
  </div>
  ```

- [ ] **Step 2: Add the breadcrumb element above the input and update footer copy**

  Replace only the content inside the `modal-box` div. The `<form method="dialog" class="modal-backdrop">` that follows the `modal-box` is **not part of this replacement** — leave it untouched.

  New `modal-box` content:
  ```html
  <div class="modal-box max-w-2xl p-0 overflow-hidden">
    <div class="border-b border-base-content/10 p-3">
      <div
        data-palette-breadcrumb
        class="hidden text-[11px] text-base-content/50 mb-2 select-none"
      ></div>
      <label for="command-palette-input" class="sr-only">Search commands</label>
      <input
        id="command-palette-input"
        type="text"
        data-palette-input
        placeholder="Search commands..."
        class="w-full h-10 rounded-lg border border-base-content/10 bg-base-100 px-3 text-sm focus:outline-none focus:border-primary/40"
      />
    </div>
    <div
      data-palette-results
      role="listbox"
      aria-label="Command palette results"
      class="max-h-[55dvh] overflow-y-auto p-2"
    >
    </div>
    <div class="px-3 py-2 text-[11px] text-base-content/55 border-t border-base-content/10">
      ↑↓ to move · Enter to select · Esc to close/back · Backspace to go back
    </div>
  </div>
  ```

  Note: placeholder changed from "Search pages, projects, and commands..." to "Search commands..."

- [ ] **Step 3: Verify `mix compile` passes**

  Run: `cd /Users/urielmaldonado/projects/eits/web && mix compile`
  Expected: No errors

- [ ] **Step 4: Commit**

  ```bash
  git add lib/eye_in_the_sky_web_web/components/layouts/app.html.heex
  git commit -m "feat(palette): add breadcrumb element and update footer copy"
  ```

---

## Chunk 2: CommandRegistry

### Task 3: Add `CommandRegistry` module inline in `app.js`

Note: The keyboard trigger (platform detection + focus guard) is part of the `Hooks.CommandPalette` rewrite in Chunk 3. This task only registers the command data.

**Files:**
- Modify: `assets/js/app.js` (add before `Hooks.CommandPalette`)

- [ ] **Step 1: Locate the `Hooks.CommandPalette = {` line**

  It currently starts at ~line 519. Add the `CommandRegistry` block immediately before it.

- [ ] **Step 2: Insert the CommandRegistry module**

  ```js
  // ---------------------------------------------------------------------------
  // CommandRegistry — flat discriminated union of all palette commands
  // ---------------------------------------------------------------------------

  function getCommands() {
    return [
      // --- Workspace navigation ---
      { id: "go-sessions",      label: "Sessions",      icon: "hero-cpu-chip",                  group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/",              when: null },
      { id: "go-tasks",         label: "Tasks",         icon: "hero-clipboard-document-list",   group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/tasks",          when: null },
      { id: "go-notes",         label: "Notes",         icon: "hero-document-text",             group: "Workspace", hint: "Workspace", keywords: [],                        shortcut: null, type: "navigate", href: "/notes",          when: null },
      { id: "go-usage",         label: "Usage",         icon: "hero-chart-bar",                 group: "Insights",  hint: "Insights",  keywords: ["analytics", "stats"],    shortcut: null, type: "navigate", href: "/usage",          when: null },
      { id: "go-prompts",       label: "Prompts",       icon: "hero-book-open",                 group: "Knowledge", hint: "Knowledge", keywords: [],                        shortcut: null, type: "navigate", href: "/prompts",        when: null },
      { id: "go-skills",        label: "Skills",        icon: "hero-bolt",                      group: "Knowledge", hint: "Knowledge", keywords: [],                        shortcut: null, type: "navigate", href: "/skills",         when: null },
      { id: "go-notifications", label: "Notifications", icon: "hero-bell",                      group: "Knowledge", hint: "Knowledge", keywords: ["alerts"],                shortcut: null, type: "navigate", href: "/notifications",  when: null },
      { id: "go-jobs",          label: "Jobs",          icon: "hero-cog-6-tooth",               group: "System",    hint: "System",    keywords: ["scheduled", "cron"],     shortcut: null, type: "navigate", href: "/jobs",           when: null },
      { id: "go-settings",      label: "Settings",      icon: "hero-adjustments-horizontal",    group: "System",    hint: "System",    keywords: ["config", "preferences"], shortcut: null, type: "navigate", href: "/settings",       when: null },

      // --- Actions ---
      {
        id: "create-task",
        label: "Create Task",
        icon: "hero-plus",
        group: "Tasks",
        hint: null,
        keywords: ["new", "add", "todo"],
        shortcut: null,
        type: "callback",
        fn: () => { window.location.assign("/tasks?intent=create") },
        when: null
      },
      {
        id: "toggle-theme",
        label: "Toggle Theme",
        icon: "hero-moon",
        group: "System",
        hint: null,
        keywords: ["dark", "light", "mode"],
        shortcut: null,
        type: "callback",
        fn: () => {
          const current = document.documentElement.getAttribute("data-theme") || localStorage.getItem("theme") || "light"
          const next = current === "dark" ? "light" : "dark"
          localStorage.setItem("theme", next)
          document.documentElement.setAttribute("data-theme", next)
          document.querySelectorAll(".theme-controller").forEach(c => {
            if (c.type === "checkbox") c.checked = next === "dark"
          })
        },
        when: null
      },
      {
        id: "copy-url",
        label: "Copy Current URL",
        icon: "hero-link",
        group: "System",
        hint: null,
        keywords: ["clipboard", "share", "link"],
        shortcut: null,
        type: "callback",
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
        },
        when: null
      },

      // --- Submenus ---
      {
        id: "go-project",
        label: "Go to Project...",
        icon: "hero-folder",
        group: "Projects",
        hint: null,
        keywords: ["open", "switch", "navigate"],
        shortcut: null,
        type: "submenu",
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
        },
        when: null
      }
    ]
  }
  ```

- [ ] **Step 3: Run `mix compile` to verify no syntax errors**

  Run: `cd /Users/urielmaldonado/projects/eits/web && mix compile`
  Expected: No errors

- [ ] **Step 4: Commit**

  ```bash
  git add assets/js/app.js
  git commit -m "feat(palette): add CommandRegistry with initial command set"
  ```

---

## Chunk 3: Hooks.CommandPalette Rewrite

### Task 4: Replace `Hooks.CommandPalette` with the new implementation

**Files:**
- Modify: `assets/js/app.js` — replace the entire `Hooks.CommandPalette = { ... }` block

- [ ] **Step 1: Delete the old `Hooks.CommandPalette` block entirely**

  Remove from `Hooks.CommandPalette = {` through the closing `}` (~lines 519–759). Keep `CommandRegistry` (just added) and everything below intact.

- [ ] **Step 2: Insert the new `Hooks.CommandPalette` block immediately after `CommandRegistry`**

  ```js
  Hooks.CommandPalette = {
    mounted() {
      this.input = this.el.querySelector("[data-palette-input]")
      this.results = this.el.querySelector("[data-palette-results]")
      this.breadcrumb = this.el.querySelector("[data-palette-breadcrumb]")
      this.stack = []
      this.activeIndex = 0
      this.visibleItems = []

      this._isMac = navigator.userAgentData
        ? navigator.userAgentData.platform === "macOS"
        : navigator.platform.toUpperCase().includes("MAC")

      this._globalKeyHandler = (e) => {
        if ((this._isMac ? e.metaKey : e.ctrlKey) && e.key.toLowerCase() === "k") {
          const inEditor = document.activeElement?.closest(".cm-editor, .monaco-editor, [data-palette-no-intercept]")
          if (inEditor) return
          e.preventDefault()
          this.open()
        }
      }
      window.addEventListener("keydown", this._globalKeyHandler)

      this._openHandler = () => this.open()
      this.el.addEventListener("palette:open", this._openHandler)

      this.input?.addEventListener("input", () => {
        this.activeIndex = 0
        this.render()
      })
      this.input?.addEventListener("keydown", (e) => this.onInputKeydown(e))

      this._resultsClickHandler = (e) => {
        const btn = e.target.closest("button[data-index]")
        if (!btn) return
        const idx = Number(btn.dataset.index)
        const cmd = this.visibleItems[idx]
        if (cmd) this.activate(cmd)
      }
      this.results?.addEventListener("click", this._resultsClickHandler)
    },

    destroyed() {
      window.removeEventListener("keydown", this._globalKeyHandler)
      this.el.removeEventListener("palette:open", this._openHandler)
      this.results?.removeEventListener("click", this._resultsClickHandler)
    },

    open() {
      this.stack = []
      this.activeIndex = 0
      this.el.showModal()
      if (this.input) {
        this.input.value = ""
        this.input.focus()
      }
      this.updateBreadcrumb()
      this.render()
    },

    activeCommands() {
      if (this.stack.length === 0) return getCommands()
      return this.stack[this.stack.length - 1].commands
    },

    filteredItems() {
      const q = (this.input?.value || "").trim().toLowerCase()
      const cmds = this.activeCommands().filter(cmd => !cmd.when || cmd.when())

      if (!q) {
        if (this.stack.length === 0) {
          const recent = this.loadRecent()
          const byHref = new Map(cmds.filter(c => c.type === "navigate").map(c => [c.href, c]))
          const recentItems = recent
            .map(r => byHref.get(r.href))
            .filter(Boolean)
            .filter(cmd => !cmd.when || cmd.when())
          const recentHrefs = new Set(recentItems.map(c => c.href))
          const rest = cmds.filter(c => !recentHrefs.has(c.href))
          return [...recentItems, ...rest].slice(0, 40)
        }
        return cmds.slice(0, 40)
      }

      return cmds
        .map(cmd => {
          const positions = this.fuzzyPositions(cmd.label, q)
          return { cmd, score: this.scoreCmd(cmd, q, positions), positions }
        })
        .filter(({ score }) => score > 0)
        .sort((a, b) => b.score - a.score || a.cmd.label.localeCompare(b.cmd.label))
        .slice(0, 40)
        .map(({ cmd, positions }) => ({ ...cmd, _matchPositions: positions }))
    },

    scoreCmd(cmd, q, positions) {
      const label = cmd.label.toLowerCase()
      let score = 0

      if (label === q) score += 200
      if (label.startsWith(q)) score += 100
      if (label.includes(q)) score += 50

      if (positions !== null) {
        score += 60
        let consecutive = 0
        for (let i = 1; i < positions.length; i++) {
          if (positions[i] === positions[i - 1] + 1) consecutive++
        }
        score += consecutive * 2
      }

      const kws = (cmd.keywords || []).join(" ").toLowerCase()
      if (kws && kws.includes(q)) score += 30
      if (cmd.hint && cmd.hint.toLowerCase().includes(q)) score += 15
      if (cmd.group && cmd.group.toLowerCase().includes(q)) score += 10

      return score
    },

    fuzzyPositions(label, q) {
      const lc = label.toLowerCase()
      const positions = []
      let qi = 0
      for (let i = 0; i < lc.length && qi < q.length; i++) {
        if (lc[i] === q[qi]) { positions.push(i); qi++ }
      }
      return qi === q.length ? positions : null
    },

    render() {
      if (!this.results) return
      const items = this.filteredItems()
      this.visibleItems = items
      if (this.activeIndex >= items.length) this.activeIndex = 0

      if (items.length === 0) {
        this.results.innerHTML = `<div class="px-3 py-4 text-sm text-base-content/50">No matches</div>`
        return
      }

      const q = (this.input?.value || "").trim()
      const grouped = !q && this.stack.length === 0

      this.results.innerHTML = grouped ? this.renderGrouped(items) : this.renderFlat(items)

      const active = this.results.querySelector(`button[data-index="${this.activeIndex}"]`)
      if (active) active.scrollIntoView({ block: "nearest" })
    },

    renderGrouped(items) {
      const groupOrder = ["Workspace", "Projects", "Tasks", "Insights", "Knowledge", "Communication", "System"]
      const groups = new Map()
      for (const item of items) {
        const g = item.group || "Other"
        if (!groups.has(g)) groups.set(g, [])
        groups.get(g).push(item)
      }

      let idx = 0
      return [...groups.entries()]
        .sort((a, b) => {
          const ai = groupOrder.indexOf(a[0])
          const bi = groupOrder.indexOf(b[0])
          return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi) || a[0].localeCompare(b[0])
        })
        .map(([group, groupItems]) => {
          const buttons = groupItems.map(item => this.renderRow(item, idx++, null)).join("")
          return `<section class="px-1 py-1"><h3 class="px-2 py-1 text-[10px] uppercase tracking-wider text-base-content/40">${this.escapeHtml(group)}</h3><div>${buttons}</div></section>`
        }).join("")
    },

    renderFlat(items) {
      return `<div class="px-1 py-1">${items.map((item, i) => this.renderRow(item, i, item._matchPositions || null)).join("")}</div>`
    },

    renderRow(item, idx, matchPositions) {
      const isActive = idx === this.activeIndex
      const labelHtml = matchPositions
        ? this.highlightLabel(item.label, new Set(matchPositions))
        : this.escapeHtml(item.label)

      const hintHtml = item.hint
        ? `<div class="text-xs text-base-content/45 truncate">${this.escapeHtml(item.hint)}</div>`
        : ""

      const shortcutHtml = item.shortcut
        ? item.shortcut.split(" ").map(k => `<kbd class="text-[10px] px-1 py-0.5 rounded border border-base-content/20 text-base-content/50">${this.escapeHtml(k)}</kbd>`).join(" ")
        : ""

      const chevronHtml = item.type === "submenu"
        ? `<span class="hero-chevron-right w-3 h-3 text-base-content/40 shrink-0"></span>`
        : ""

      const rightHtml = (shortcutHtml || chevronHtml)
        ? `<div class="flex items-center gap-1 ml-2 shrink-0">${shortcutHtml}${chevronHtml}</div>`
        : ""

      return `<button type="button" data-index="${idx}" role="option" aria-selected="${isActive}" class="w-full text-left rounded-lg px-3 py-2 text-sm flex items-center gap-2 transition-colors ${isActive ? "bg-base-200 text-base-content" : "hover:bg-base-200/70 text-base-content/80"}"><span class="${this.escapeHtml(item.icon)} w-4 h-4 shrink-0 text-base-content/50"></span><div class="flex-1 min-w-0"><div class="font-medium truncate">${labelHtml}</div>${hintHtml}</div>${rightHtml}</button>`
    },

    highlightLabel(label, matchedPositions) {
      return [...label].map((char, i) =>
        matchedPositions.has(i)
          ? `<mark class="bg-transparent text-primary font-semibold">${this.escapeHtml(char)}</mark>`
          : this.escapeHtml(char)
      ).join("")
    },

    updateBreadcrumb() {
      if (!this.breadcrumb) return
      if (this.stack.length === 0) {
        this.breadcrumb.classList.add("hidden")
        this.breadcrumb.textContent = ""
      } else {
        this.breadcrumb.classList.remove("hidden")
        this.breadcrumb.textContent = ["Commands", ...this.stack.map(s => s.label)].join(" › ")
      }
    },

    onInputKeydown(e) {
      const items = this.visibleItems || []
      const len = Math.max(items.length, 1)

      if (e.key === "ArrowDown") {
        e.preventDefault()
        this.activeIndex = (this.activeIndex + 1) % len
        this.render()
      } else if (e.key === "ArrowUp") {
        e.preventDefault()
        this.activeIndex = (this.activeIndex - 1 + len) % len
        this.render()
      } else if (e.key === "Enter") {
        e.preventDefault()
        const cmd = items[this.activeIndex]
        if (cmd) this.activate(cmd)
      } else if (e.key === "Escape") {
        e.preventDefault()
        if (this.stack.length > 0) {
          this.stack.pop()
          this.activeIndex = 0
          if (this.input) this.input.value = ""
          this.updateBreadcrumb()
          this.render()
        } else {
          this.el.close()
        }
      } else if (e.key === "Backspace" && !e.isComposing) {
        if ((this.input?.value || "") === "" && this.stack.length > 0) {
          e.preventDefault()
          this.stack.pop()
          this.activeIndex = 0
          this.updateBreadcrumb()
          this.render()
        }
      }
    },

    activate(cmd) {
      if (cmd.type === "navigate") {
        this.saveRecent(cmd)
        this.el.close()
        window.location.assign(cmd.href)
      } else if (cmd.type === "callback") {
        this.el.close()
        cmd.fn()
      } else if (cmd.type === "submenu") {
        const resolved = typeof cmd.commands === "function" ? cmd.commands() : cmd.commands
        this.stack.push({ id: cmd.id, label: cmd.label, commands: resolved })
        this.activeIndex = 0
        if (this.input) this.input.value = ""
        this.updateBreadcrumb()
        this.render()
      }
    },

    loadRecent() {
      try {
        const parsed = JSON.parse(localStorage.getItem("command_palette_recent") || "[]")
        return Array.isArray(parsed) ? parsed : []
      } catch (_) { return [] }
    },

    saveRecent(cmd) {
      if (cmd.type !== "navigate") return
      const existing = this.loadRecent().filter(e => e.href !== cmd.href)
      const next = [{ id: cmd.id, label: cmd.label, href: cmd.href, at: Date.now() }, ...existing].slice(0, 8)
      localStorage.setItem("command_palette_recent", JSON.stringify(next))
    },

    escapeHtml(value) {
      return String(value || "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;")
    }
  }
  ```

- [ ] **Step 3: Confirm only one `Hooks.CommandPalette` block exists in the file**

  Run: `grep -n "Hooks.CommandPalette" assets/js/app.js`
  Expected: Exactly one line

- [ ] **Step 4: Run `mix compile`**

  Run: `cd /Users/urielmaldonado/projects/eits/web && mix compile`
  Expected: No errors

- [ ] **Step 5: Smoke test in browser**

  Open `http://localhost:5001`, press Cmd+K (macOS):
  - Palette opens, breadcrumb hidden
  - Type "ta" — "Tasks" and "Create Task" appear with highlighted chars
  - Arrow keys move selection, wraps at boundaries
  - Press Enter on "Tasks" — navigates to `/tasks`
  - Reopen, type "pro" — "Go to Project..." with chevron appears
  - Press Enter — breadcrumb shows "Commands › Go to Project...", project list appears
  - Press Escape — back to root, breadcrumb hidden
  - Press Escape again — palette closes
  - Reopen, click "Toggle Theme" — theme switches

- [ ] **Step 6: Commit**

  ```bash
  git add assets/js/app.js
  git commit -m "feat(palette): rewrite CommandPalette hook with stack navigation, fuzzy match, and submenus"
  ```

---

## Chunk 4: Tasks LiveView — `?intent=create`

### Task 5: Wire `NewTaskDrawer` into `OverviewLive.Tasks` and open on `?intent=create`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/tasks.ex`

- [ ] **Step 1: Add `show_create_task_drawer: false` to `mount/3` assigns**

  In `mount/3`, add to the socket pipeline (after the existing assigns):
  ```elixir
  |> assign(:show_create_task_drawer, false)
  ```

- [ ] **Step 2: Add `handle_params/3` after `mount/3`**

  ```elixir
  @impl true
  def handle_params(%{"intent" => "create"}, _uri, socket) do
    {:noreply, assign(socket, :show_create_task_drawer, true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end
  ```

- [ ] **Step 3: Add toggle and create event handlers**

  Add after the existing `handle_event` clauses:
  ```elixir
  @impl true
  def handle_event("toggle_create_task_drawer", _params, socket) do
    {:noreply, assign(socket, :show_create_task_drawer, !socket.assigns.show_create_task_drawer)}
  end

  @impl true
  def handle_event("create_new_task", params, socket) do
    title = params["title"]
    description = params["description"]
    state_id = parse_int(params["state_id"], 0)

    case Tasks.create_task(%{
      title: title,
      description: description,
      state_id: if(state_id > 0, do: state_id, else: 1),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> assign(:show_create_task_drawer, false)
         |> load_tasks()
         |> put_flash(:info, "Task created")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create task")}
    end
  end
  ```

  Verify `parse_int/2` is imported — it comes from `EyeInTheSkyWebWeb.ControllerHelpers`. Check the top of the module; add the import if absent:
  ```elixir
  import EyeInTheSkyWebWeb.ControllerHelpers, only: [parse_int: 2]
  ```

- [ ] **Step 4: Add `NewTaskDrawer` component at the end of the template's main container**

  Find the `def render(assigns)` function and locate the closing `</div>` of the outermost content wrapper. Add before it:
  ```heex
  <.live_component
    module={EyeInTheSkyWebWeb.Components.NewTaskDrawer}
    id="tasks-new-task-drawer"
    show={@show_create_task_drawer}
    workflow_states={@workflow_states}
    toggle_event="toggle_create_task_drawer"
    submit_event="create_new_task"
  />
  ```

- [ ] **Step 5: Run `mix compile`**

  Run: `cd /Users/urielmaldonado/projects/eits/web && mix compile`
  Expected: No errors

- [ ] **Step 6: Smoke test**

  - Open `http://localhost:5001/tasks?intent=create`
  - Drawer opens automatically
  - Fill title, submit — task appears in list, drawer closes
  - Navigate to `/tasks` directly — drawer is closed

- [ ] **Step 7: Commit**

  ```bash
  git add lib/eye_in_the_sky_web_web/live/overview_live/tasks.ex
  git commit -m "feat(tasks): open NewTaskDrawer on /tasks?intent=create"
  ```

---

## Post-implementation cleanup

- [ ] **Delete the superseded root-level draft doc**

  ```bash
  git rm command-palette-linear-style-redesign.md
  git commit -m "chore: remove superseded command palette draft doc"
  ```

- [ ] **Final compile check**

  Run: `cd /Users/urielmaldonado/projects/eits/web && mix compile`
  Expected: No errors

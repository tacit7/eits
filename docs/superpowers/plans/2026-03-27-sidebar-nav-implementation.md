# Sidebar Nav Redesign — Implementation Plan

**Date:** 2026-03-27
**Spec:** `docs/superpowers/specs/2026-03-27-sidebar-nav-redesign.md`
**Status:** Ready to implement

---

## Actual Architecture (read before coding)

The codebase does not have a root layout LiveView or shared parent LiveView that owns the sidebar. Actual structure:

- One `live_session :app` with `on_mount: [AuthHook, FabHook, NavHook]`
- `NavHook` sets only `nav_path` and `mobile_nav_tab` — no sidebar assigns
- `sidebar_project` is **URL-driven**: set by `ProjectLiveHelpers.mount_project/3` on every project route, `nil` on all other routes
- The `Sidebar` is a **stateless LiveComponent** — receives assigns from the hosting LiveView, does not own state
- `ProjectLiveHelpers` already handles nil and not-found: invalid project ID → `sidebar_project: nil`, flash error

### Sidebar state ownership

| Assign | Owner | Set by |
|--------|-------|--------|
| `sidebar_tab` | hosting LiveView | each LiveView's `mount/3` |
| `sidebar_project` | hosting LiveView | `ProjectLiveHelpers.mount_project/3` on project routes; `nil` elsewhere |

There is no floating session state to invent. `sidebar_project` follows the URL. This is correct and stays that way.

### What "clicking a project row" means

Clicking a project row **navigates to `/projects/:id`**. It does not set sidebar context independently of the URL. The docked panel appears because the user is on a project route and `sidebar_project` is loaded from params. This eliminates any invented persistence problem.

### Sidebar state ownership rules (codified)

- `sidebar_project` is owned by `ProjectLiveHelpers` and individual project LiveViews
- Project row clicks are `<.link navigate>` calls — not `phx-click` events
- The Sidebar component does not handle `select_project` as a LiveView event
- Individual page LiveViews must not assign `sidebar_project` directly — use `ProjectLiveHelpers.mount_project/3`
- Non-project LiveViews assign `sidebar_project: nil`, which renders a flat project list

---

## Steps

### Step 1 — Audit current sidebar assigns

Before touching any component, map the existing state flow.

- [ ] Confirm every project LiveView uses `ProjectLiveHelpers.mount_project/3` — not direct assigns
- [ ] Confirm all non-project LiveViews assign `sidebar_tab` and `sidebar_project: nil` consistently
- [ ] Check what `sidebar_tab` atom `ProjectLive.Show` sets — this is the Overview active state
- [ ] Confirm Sidebar is always invoked as a `live_component` receiving both assigns as attrs
- [ ] Note any LiveView that assigns `sidebar_project` directly (not through the helper) — normalize if found

---

### Step 2 — Refactor `ProjectsSection`

**File:** `lib/eye_in_the_sky_web_web/components/sidebar/projects_section.ex`

Current: inline JS expand/collapse via `data-project-toggle`.
Target: flat list; docked panel renders below the row matching `@sidebar_project.id`.

- [ ] Remove all `data-project-toggle` JS accordion logic and markup
- [ ] Project rows use `<.link navigate={~p"/projects/#{project.id}"}>` — no `phx-click`
- [ ] Apply selected class when `@sidebar_project && @sidebar_project.id == project.id`
- [ ] After the matching row, conditionally render the docked panel:

```heex
<%= if @sidebar_project && @sidebar_project.id == project.id do %>
  <div class="project-panel">
    <div class="project-panel-header">
      <span class="project-panel-name"><%= @sidebar_project.name %></span>
    </div>
    <!-- panel nav items -->
  </div>
<% end %>
```

- [ ] Panel nav items use `<.link navigate={~p"/projects/#{@sidebar_project.id}/sessions"}>` etc. — no `phx-click`
- [ ] Panel nav order: Overview (`/projects/:id`), Sessions, Tasks, Prompts, Notes, Files, Agents, Jobs
- [ ] Each panel item is a separate row with its own icon. No dot-compressed text.
- [ ] Overview is active when `@sidebar_tab == <atom set by ProjectLive.Show>` (confirm in Step 1)
- [ ] All other panel items active when `@sidebar_tab` matches their atom (`:sessions`, `:tasks`, etc.)

**Failure case:** `ProjectLiveHelpers` already handles invalid IDs by assigning `sidebar_project: nil`. No extra handling needed here — the flat list renders automatically when nil.

---

### Step 3 — Update `SystemSection`

**File:** `lib/eye_in_the_sky_web_web/components/sidebar/system_section.ex`

- [ ] Split Config, Jobs, Settings into three separate nav rows
- [ ] Config: gear icon, `navigate={~p"/config"}`
- [ ] Jobs: clock icon, `navigate={~p"/jobs"}`
- [ ] Settings: list icon, `navigate={~p"/settings"}`
- [ ] No dot-compressed text

---

### Step 4 — Update `Sidebar` section ordering and workspace nav

**File:** `lib/eye_in_the_sky_web_web/components/sidebar.ex`

- [ ] Section order: Workspace → Chat → Projects → System
- [ ] Workspace section: Sessions, Tasks, Prompts, Notes (global routes, not project-scoped)
- [ ] Remove the old "Overview/all_projects" section — workspace items replace it at the top
- [ ] Workspace items are active when `@sidebar_tab` matches AND `@sidebar_project` is nil
- [ ] Do not change how `sidebar_project` is assigned — that is owned by the project LiveViews

---

### Step 5 — CSS / Tailwind

Use existing semantic conventions from the project (`text-primary`, `bg-primary/10`, `border-primary`). Do not introduce new CSS variables or cargo-cult exact color values from the mockup.

Target behavior:

| Element | Treatment |
|---------|-----------|
| Selected project row | Stronger bg tint, brighter text, font-weight up, accent left border, accent-colored icon |
| Docked panel wrapper | Zero gap from row, accent top border (strongest edge), barely-visible sides and bottom, faint accent bg tint |
| Panel header | Project name only, normal case, small font, accent color. No icon. No "Project" label. |
| Panel nav item | Separate row, own icon, border-left active indicator matching existing sidebar active treatment |

Check existing `bg-primary/10`, `border-l-2 border-primary`, `text-primary` usage in the current sidebar markup. Match those conventions.

---

### Step 6 — Tests

- [ ] Render test: `sidebar_project: nil` → flat project list, no panel rendered
- [ ] Render test: `sidebar_project` set → matching row has selected class, panel renders beneath it
- [ ] Render test: non-matching project rows have no panel
- [ ] Render test: panel has 8 separate rows (Overview through Jobs) — no dot-compressed text
- [ ] Render test: panel header contains project name, no icon, no "Project" label
- [ ] Render test: Overview panel item active when `sidebar_tab` matches `ProjectLive.Show` atom
- [ ] Render test: project row renders as a `<a>` link to `/projects/:id`, not a button or phx-click
- [ ] Existing `ProjectLiveHelpers` test: invalid project ID → `sidebar_project: nil` (add if missing)

---

### Step 7 — Compile and manual verify

- [ ] `mix compile` — zero errors
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `PORT=5002 DISABLE_AUTH=true mix phx.server`
- [ ] Click a project row from a workspace page → navigates to `/projects/:id`, panel appears
- [ ] Click another project row → navigates to that project, panel updates
- [ ] Navigate to a workspace route (`/sessions`) → flat project list, no panel
- [ ] Navigate to `/projects/<invalid-id>` → nil panel state, flash error, no crash
- [ ] System section: Config, Jobs, Settings as separate rows

---

### Step 8 — Commit and PR

- [ ] `git add` only changed files
- [ ] `mix compile --warnings-as-errors` passes before committing
- [ ] Commit: `feat: sidebar nav redesign — docked project panel, flat structure, URL-driven selection`
- [ ] Push worktree branch, open PR against main
- [ ] Reference spec in PR description

---

## Out of Scope

- Project Overview page content (separate spec needed)
- Command palette project switching
- Arrow-key navigation
- Any additions to the docked panel beyond the 8 nav items
- Session-level persistence of sidebar selection — URL is the state, no persistence needed

# Sidebar Nav Redesign

**Date:** 2026-03-27
**Status:** Design approved, pending implementation

---

## Problem

The current sidebar has structural and hierarchy problems:

- Too many equal-weight top-level concepts with no clear grouping
- "Overview" section pretends to be global workspace nav but contains project-level items (Sessions, Tasks, Prompts, etc.)
- Inline project sub-nav expands inside the project list, adding visual noise and breaking the list's scannability
- Weak active states — selected items don't read as clearly selected
- Chat channels and projects blend together visually despite being unrelated concepts
- System items (Config, Jobs, Settings) compressed into a single dot-separated row
- No clear hierarchy between project row and its sub-navigation

---

## Decision

**Option A: Context Switch with Docked Panel**

When a project is selected, a local nav panel docks immediately below the selected project row. The panel is visually subordinate to the row — it's an extension, not a sibling card. When no project is selected, the panel is completely absent; the project list is flat and clean.

**Rejected:** Option B (accordion inline expand) — expands inline within the project list, breaking scanability of the list itself and creating "two equally strong boxes stacked" problem.

---

## Structure

```
Workspace
  Sessions
  Tasks
  Prompts
  Notes

Chat
  # general
  # dev
  ...

Projects
  eits-web
  discourse          ← selected row (accent left border, brighter text, stronger bg)
  ┌─────────────┐   ← docked panel (accent top only, soft sides/bottom)
  │ Discourse   │
  │  Overview   │   ← active on every project switch
  │  Sessions   │
  │  Tasks      │
  │  Prompts    │
  │  Notes      │
  │  Files      │
  │  Agents     │
  │  Jobs       │
  └─────────────┘
  sagents

System
  Config
  Jobs
  Settings
```

---

## Design Decisions

### 1. Docked panel, not card

The panel must feel attached to the selected row, not inserted beneath it as a sibling element.

- **Zero gap** between selected row and panel top edge
- Left edge of panel indents `14px` to sit inside the row's left-border zone
- Panel top border: `1.5px solid accent` — the strongest edge, forming the visual connection
- Panel sides + bottom: `rgba(accent, 0.12–0.15)` — present but not competing
- Panel background: `rgba(accent, 0.03)` — subtle tint, not a card background

CSS model:
```css
.project-panel {
  margin: 0 0 4px 14px;
  border-top: 1.5px solid var(--accent);
  border-right: 1px solid rgba(99,102,241,0.15);
  border-bottom: 1px solid rgba(99,102,241,0.12);
  border-left: none;
  border-radius: 0 0 4px 0;
  background: rgba(99,102,241,0.03);
}
```

### 2. Selected project row

Needs to be unmistakably active from a glance. Currently too weak.

```css
.project-row.selected {
  color: #c7d2fe;                        /* brighter indigo, above accent2 */
  background: rgba(99,102,241,0.13);     /* stronger than standard active */
  border-left: 2px solid var(--accent);
  font-weight: 600;
}
```

The accent folder icon color is also applied on the selected row.

### 3. Panel header

No icon. No "Project" label. Just the project name in normal case, `font-size: 11px`, `color: accent2`.

The repeated icon + all-caps project name created too much noise. The visual connection (accent top border, matching bg tint) already communicates the relationship. The header just needs to confirm which project is selected.

```html
<div class="project-panel-header">
  <span class="project-panel-name">Discourse</span>
</div>
```

### 4. Panel navigation order

```
Overview      (home icon — always first, always resets active on project switch)
Sessions
Tasks
Prompts
Notes
Files
Agents
Jobs
```

All items are separate rows with their own icon. No dot-compressed text.

**Overview:** Valid label in this context — it means project landing page (summary, recent activity, counts, quick links). Distinct from the former "Overview" section which pretended to be global workspace nav.

### 5. Collapsible panel

When no project is selected, the panel is completely hidden. No collapsed stub, no empty placeholder. The project list renders as a flat, clean list of folder-icon rows.

State: `socket.assigns.sidebar_project` is `nil` when nothing is selected.

### 6. Project switching

Click any project row → `phx-click="select_project"` event → LiveView updates `sidebar_project` assign → panel re-renders with new project name, Overview resets to active.

No animation required. The structural clarity carries the transition. Arrow keys and command palette (`⌘K → switch project`) are future fast-switch paths.

### 7. Section icons

Icons are the primary peripheral-vision signal for section identity:

| Section | Icon |
|---------|------|
| Workspace items | destination-specific (grid, calendar, book, pencil) |
| Chat channels | hash (`#`) icon |
| Projects | folder icon |
| Panel items | destination-specific (home, grid, calendar, book, pencil, folder, users, clock) |
| System | gear, clock, list |

### 8. System section

Config, Jobs, and Settings are separate destinations. They render as separate rows with individual icons. Never compressed into dot-separated text.

### 9. Panel scope constraint

The docked panel is a **local navigation panel only**. It must not become a mini dashboard.

Prohibited additions to the panel:
- Project stats or counts
- Inline create actions
- Unread / status pills
- Recent activity feed
- Hover menus
- Environment badges

If project metadata is needed, it belongs on the project Overview page (main content area), not in the sidebar.

---

## Component Map

| Component | File | Change |
|-----------|------|--------|
| `Sidebar` | `lib/eye_in_the_sky_web_web/components/sidebar.ex` | Add `sidebar_project` assign; restructure section ordering |
| `ProjectsSection` | `lib/eye_in_the_sky_web_web/components/sidebar/projects_section.ex` | Replace inline expand with docked panel; `select_project` event; flat list when `sidebar_project` is nil |
| `SystemSection` | `lib/eye_in_the_sky_web_web/components/sidebar/system_section.ex` | Split Config/Jobs/Settings into separate rows |
| All LiveViews rendering the sidebar | Various | Thread `sidebar_project` assign — **highest implementation risk, not a footnote** |

**State threading is the primary implementation risk.** If multiple LiveViews handle `select_project` independently, `sidebar_project` will drift and reset on navigation. Single source of truth: handle `select_project` in the root layout LiveView (or a shared on-mount hook), store in Plug session, pass down as assign on every mount. Do not handle it locally per-LiveView.

---

## Open Questions

1. **Persistence — resolved direction:** `sidebar_project` persists for the browser session. Store in the Plug session so it survives LiveView navigation without URL pollution. Root layout LiveView reads it on mount and passes to the sidebar component. `select_project` event updates both socket assign and Plug session value.

2. **Overview reset on project switch — product decision:** Switching projects always lands on Overview, regardless of which panel item was previously active. Deliberate v1 choice. The alternative (restoring equivalent section across switch) adds complexity for unclear benefit.

3. **Overview page content:** Needs a separate spec before the route is implemented. At minimum: recent sessions, open tasks count, last activity timestamp. Do not ship as a blank or redirect — it will erode trust in the nav quickly.

4. **Future panel grouping:** Once the panel grows, a flat list may need lightweight grouping (Work: Sessions/Tasks/Prompts/Notes; Assets: Files; Automation: Agents/Jobs). Not needed now.

5. **Project creation:** Where does "new project" go? Out of scope for this redesign.

---

## Implementation Plan

See `docs/superpowers/plans/2026-03-27-sidebar-nav-implementation.md` (to be written).

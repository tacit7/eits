# EITS Chrome System

Formal specification for the EITS application shell: zones, page archetypes, top bar contract, component slots, migration plan, and anti-patterns. Every page in the app is one of five archetypes. Use this document when scaffolding new pages, modifying the top bar, or auditing existing pages.

---

## 1. Archetype Spec

### Archetype 1 — Index / List

**Pages:** Sessions, Tasks, Notes, Teams, Prompts, Skills, IAM, Jobs

**Layout:**
- Content: `px-4 sm:px-6 py-6`
- Top bar: present, full toolbar
- Mobile: bottom nav visible; CTA moves to a fixed bar above the list (not in top bar)

**Top bar slot order:**
```
[page name] │ [search input] [filter pills] [sort dropdown] ──flex-1── [CTA]
```

**Rules:**
- Filter = pill group (state is visible at a glance, not collapsed)
- Sort = dropdown button `Sort: X ▾` (incidental, collapses to save space)
- One CTA max, always `+ Label`
- Column controls (visibility, density) belong in the content frame, never the top bar
- No `<select>` elements anywhere in the top bar

**Notes variant:** Secondary action (Quick Note) uses a bordered ghost button between search and filter pills. Still only one primary CTA.

---

### Archetype 2 — Board / Work Surface

**Pages:** Kanban

**Layout:**
- Content: `padding: 0`, internal scroll columns
- Top bar: present, toolbar with view toggle
- Mobile: bottom nav visible

**Top bar slot order — default:**
```
[page name] │ [search input] [Filters btn] [view toggle pills] ──flex-1── [CTA]
```

**Top bar slot order — selection mode active:**
```
[page name] │ [N selected] [Done] [Clear] [Delete] ──flex-1── [Cancel]
```

**Rules:**
- No sort control — board is position-ordered, sort is meaningless
- View toggle (Board / List) is a pill group; it controls rendering mode, not data filter
- Filters is a single button that opens a panel — not exposed inline (too many dimensions)
- Selection mode replaces the entire toolbar. Normal controls are hidden, not disabled
- Delete is destructive: `text-error/70 hover:text-error hover:bg-error/8`
- Done is affirmative: `bg-success/15 text-success`

**LiveView note:** Selection mode state lives in socket assigns (`select_mode: true`). Use `phx-update="ignore"` on the dropdown/filter panel so it survives stream inserts during selection.

---

### Archetype 3 — Detail / Workspace

**Pages:** DM session, Chat

**Layout:**
- Content: `padding: 0`, internal scroll (message list owns its own scroll region)
- Top bar: present, object identity dominant
- Mobile: `hide_mobile_header: true` — page provides its own sticky header with equivalent nav

**Top bar slot order:**
```
[object name (bold)] │ [search input] [local tab pills] ──flex-1── [overflow menu ···]
```

**Rules:**
- Object name (agent/session name) is the primary identity — `text-[13px] font-semibold`, not `text-[12px]`
- Tabs are local subnavigation (Messages / Tasks / Commits / Notes / Context / Settings), not data filters
- Tab active state: `font-semibold text-base-content` (weight, not color or background)
- Tabs use `icon + label` — 6 tabs in a dense header justify icons as scan anchors for frequent switching
  - Messages → `hero-chat-bubble-left-ellipsis-mini`
  - Tasks → `hero-clipboard-document-list-mini`
  - Commits → `hero-code-bracket-mini`
  - Notes → `hero-document-text-mini`
  - Context → `hero-information-circle-mini`
  - Settings → `hero-cog-6-tooth-mini`
- CTA is contextual and optional — overflow menu (`···`) handles secondary actions
- No filter pills, no sort dropdown — content is chronological

**LiveView note:** Tab state drives `handle_params`. The page does not re-mount on tab switch — use `handle_params` with `push_patch` and `phx-update="ignore"` on the tab container to prevent morphdom thrash.

---

### Archetype 4 — Canvas

**Pages:** Canvas

**Layout:**
- Uses `canvas.html.heex` layout, not `app.html.heex`
- No top bar
- No mobile bottom nav
- Full viewport, no padding

**Rules:**
- Canvas toolbar is rendered inside the canvas layout, not via the global chrome
- Never use `app.html.heex` for canvas — the global rail and top bar are not present

---

### Archetype 5 — Form / Settings

**Pages:** Settings, IAM editor, Note editor, Config pages

**Layout:**
- Content: `px-4 sm:px-6 py-6`, constrained to `max-w-3xl` or `max-w-2xl`
- Top bar: present, section tabs only

**Top bar slot order:**
```
[page name] │ [section tab pills] ──flex-1──
```

**Rules:**
- No CTA in the top bar — Save / Cancel live inside the form
- No search, no filter, no sort in the top bar
- Section tabs (General / Editor / Auth / Workflow / System) navigate between settings groups
- Tab active: `font-semibold text-base-content` (same as Archetype 3)

---

## 2. Page → Archetype Mapping

| Page | Archetype | Current deviations | Priority |
|---|---|---|---|
| Sessions | 1 | Sort uses `<select>` in production | P1 |
| Tasks | 1 | Sort uses `<select>` in production | P1 |
| Notes | 1 | Sort uses `<select>`; star button is orphaned | P1 |
| Teams | 1 | Likely compliant | P3 |
| Prompts | 1 | Likely compliant | P3 |
| Skills | 1 | Likely compliant | P3 |
| IAM | 1 | Likely compliant | P3 |
| Jobs | 1 | Likely compliant | P3 |
| Kanban | 2 | No Board/List toggle yet; no selection mode | P1 |
| DM session | 3 | Mobile header suppression needs verification | P2 |
| Chat | 3 | Check tab pill active state implementation | P2 |
| Canvas | 4 | Compliant (dedicated layout) | — |
| Settings | 5 | `top_bar/1` god-object leaking here too | P2 |
| IAM editor | 5 | Check max-w constraint | P3 |
| Note editor | 5 | Check max-w constraint | P3 |

---

## 3. Component / Slot Breakdown

### Current state (the problem)

`top_bar/1` is a single component with 18+ attrs and a 7-branch `cond` block. Adding a new toolbar variant requires touching the component and adding another cond branch. It cannot be composed — callers pass a blob of attrs, not slots.

### Target: slot-based top bar

```heex
<%!-- Target API — not yet implemented --%>
<.top_bar>
  <:identity>Sessions</:identity>

  <:toolbar>
    <.tb_search placeholder="Search sessions..." />
    <.tb_filter_pills options={["All", "Working", "Archived"]} active={@filter} on_change="set_filter" />
    <.tb_sort_dropdown options={["Last message", "Name", "Agent"]} active={@sort} on_change="set_sort" />
  </:toolbar>

  <:cta>
    <.tb_cta icon="hero-plus" phx-click="new_session">New Session</.tb_cta>
  </:cta>
</.top_bar>
```

### Sub-components to extract

| Component | Renders | Attrs |
|---|---|---|
| `tb_search` | `input-xs h-7` with magnifying glass | `placeholder`, `value`, `on_change` |
| `tb_filter_pills` | `bg-base-200/40 rounded-lg p-0.5` pill group | `options`, `active`, `on_change` |
| `tb_sort_dropdown` | `Sort: X ▾` bordered button | `options`, `active`, `on_change` |
| `tb_view_toggle` | Board/List pill group with icons | `options`, `active`, `on_change` |
| `tb_action_btn` | Ghost bordered button (Filters, Quick Note) | `icon`, slot for label |
| `tb_cta` | `bg-primary h-7` primary action | `icon`, slot for label |
| `tb_selection_bar` | Replaces toolbar in selection mode | `count`, `on_done`, `on_clear`, `on_delete`, `on_cancel` |

### Shell zones

```
┌─────────────────────────────────────────────────────┐
│  Rail 56px  │  Top Bar h-10                         │
│  (always)   ├───────────────────────────────────────┤
│             │  Content Frame (flex-1 overflow-auto)  │
└─────────────┴───────────────────────────────────────┘

Mobile:
┌─────────────────────────────────────────────────────┐
│  Mobile Top Bar h-[3rem+safe-area-inset-top]        │
├─────────────────────────────────────────────────────┤
│  Content                                            │
├─────────────────────────────────────────────────────┤
│  Bottom Nav (fixed)                                 │
└─────────────────────────────────────────────────────┘
```

---

## 4. Migration Plan

### Phase 0 — Freeze (done)

Document the current state. No new pages deviate from the archetypes defined here. New pages must comply before merging.

### Phase 1 — Quick wins: eliminate `<select>` (P1)

**Target pages:** Sessions sort, Tasks sort, Notes sort and type filter

For each page:
1. Replace `<select>` with a `phx-click` pill group (filter) or dropdown button (sort)
2. Wire `handle_event("set_sort", ...)` and `handle_event("set_filter", ...)`
3. Update `list_*` calls with the new param
4. Test: sort/filter state survives LiveView reconnect

Effort per page: ~2–3 hours. No schema changes. No architecture changes.

### Phase 2 — Kanban Board/List toggle + selection mode (P1)

1. Add `view_mode` assign (`:board` | `:list`) to Kanban LiveView
2. Render board columns or task list based on assign
3. Add `select_mode` assign and `selected_task_ids` MapSet
4. Wire Done / Clear / Delete / Cancel bulk actions
5. Top bar: use selection bar template when `select_mode: true`

Effort: ~1 day.

### Phase 3 — Refactor `top_bar/1` god-object (P0)

1. Define slot-based `top_bar` component (`:identity`, `:toolbar`, `:cta` slots)
2. Extract `tb_*` sub-components as function components in `ChromeComponents`
3. Migrate one page at a time (Sessions first — simplest toolbar)
4. Delete attrs from old `top_bar/1` as they become unused
5. Remove `cond` branches as pages migrate

Effort: ~2–3 days total, can be parallelized per page.

### Phase 4 — Canonicalize content padding (P1)

Pages with non-standard padding (audit via grep for `px-` in LiveView templates):

```bash
grep -rn "px-" lib/eye_in_the_sky_web/live/ --include="*.heex"
```

Fix each Archetype 1/5 page to `px-4 sm:px-6 py-6`.

Effort: 1–2 hours, low risk.

### Phase 5 — Mobile CTA canonical slot (P1)

Currently CTA appears in two places: top bar markup and a mobile-only duplicate in the page body. Extract to a named slot `<:mobile_cta>` in the layout so there's one source of truth.

Effort: ~4 hours, touches the layout file and every Archetype 1 page.

---

## 5. Production-Ready Mockups

See the `/components` page → "Chrome System" section → "Full Page Mockups" for rendered HEEx demos of:
- Sessions page (Archetype 1 — Index / List)
- DM session page (Archetype 3 — Detail / Workspace)

---

## 6. Anti-Pattern List

### ❌ `<select>` in the top bar

**Why it's wrong:** Native select is not styleable to the `h-7` spec. It breaks the visual system, looks out of place across themes, and doesn't communicate current state as clearly as a pill.

**Fix:** Filter = pill group. Sort = `Sort: X ▾` dropdown button.

---

### ❌ Sort as a pill group

**Why it's wrong:** Sort has 3+ options (Newest / Oldest / Priority / Name / Agent). Showing all as pills uses 100–150px of top bar for something the user rarely changes. On pages with 5+ filter pills, this causes overflow or forces truncation.

**Fix:** `Sort: X ▾` bordered button. Dropdown opens on click. One option is always active, label updates inline.

---

### ❌ Filter as a dropdown (collapsed)

**Why it's wrong:** Filter state is high-value context — users need to know what they're looking at (am I seeing "All" or "In Progress"?). Collapsing it into a dropdown hides the active state.

**Fix:** Always pill group. Active pill shows current filter. Max 5 options before considering a Filters panel.

---

### ❌ Multiple CTAs in the top bar

**Why it's wrong:** Hick's law — doubling choices increases decision time. Two primary actions in the header signal unclear page ownership.

**Fix:** One CTA. Secondary actions go in the toolbar as ghost/bordered buttons (e.g., Quick Note) or in an overflow menu.

---

### ❌ Column controls or density toggles in the top bar

**Why it's wrong:** Column visibility, row density, and column resizing are user preferences for the current view, not page-level controls. They belong near the content they affect.

**Fix:** Gear icon or "Columns" button inside the content frame, above the list.

---

### ❌ `transition-all` on stream items

**Why it's wrong:** When LiveView re-inserts a stream item (e.g., after a PubSub update), any `transition-all` class causes ALL CSS properties to animate from their initial state. Opacity, transform, and color all visibly flash.

**Fix:** Never use `transition-all` inside stream item wrappers. Use targeted transitions (`transition-opacity`, `transition-colors`) only on hover-reveal children, not on the row itself.

---

### ❌ Bulk actions in the top bar for Archetype 1 (Index / List) pages

**Why it's wrong:** Bulk actions (Delete, Archive, Assign) should only appear when items are selected. Showing them in the top bar always wastes space and confuses the information hierarchy.

**Fix:** For Index/List pages, bulk actions appear inside the content frame, above the list, when items are selected. For Board pages only, selection mode replaces the toolbar (the toolbar is not cluttered by default).

---

### ❌ Object name absent from Archetype 3 (Detail / Workspace) pages

**Why it's wrong:** Users arrive at a DM/session page via navigation or direct link. Without the object name (agent name, session ID) prominently in the top bar, there's no spatial anchor. The page feels context-free.

**Fix:** Object name is `text-[13px] font-semibold` — one size larger than standard toolbar labels — and sits at the far left before the separator.

---

### ❌ Using `push_redirect` for tab switches in Archetype 3

**Why it's wrong:** `push_redirect` triggers a full LiveView mount. For a DM page, this means re-subscribing to PubSub, re-fetching the message list, and losing scroll position — all for what should be a client-side tab switch.

**Fix:** `push_patch` updates params without re-mounting. `handle_params` loads only the tab-specific data. The message list stream is preserved.

---

### ❌ Inline `background-color` or hardcoded hex in top bar elements

**Why it's wrong:** EITS has 8+ themes. Hardcoded colors break every theme except the one you designed for.

**Fix:** Use DaisyUI semantic tokens exclusively: `bg-base-100`, `bg-primary`, `text-base-content/45`, `bg-success/15`, etc. Never `style="background: #3B82F6"`.

---

### ❌ Dropdowns inside stream items without `phx-update="ignore"`

**Why it's wrong:** When a stream item is re-inserted (PubSub update), morphdom replaces the DOM node. Any open dropdown closes. Any intermediate state (hover, focus) is reset.

**Fix:** Wrap the dropdown root in `phx-update="ignore"` with a stable `id`. LiveView skips morphdom on that subtree.

```heex
<details id={"menu-#{@item.id}"} phx-update="ignore" class="dropdown dropdown-end">
```

---

## 7. Icon Usage Policy

Icons in EITS are load-bearing, not decorative. Before adding an icon, apply the two-question filter:

1. **If I remove the label, does the icon still communicate meaning?** If no, the icon is decorative — skip it.
2. **If I remove the icon, does the UI become less usable?** If no, the icon is unnecessary — skip it.

### ✅ Always use icons

| Context | Why |
|---|---|
| Rail navigation | Icons are the primary affordance — labels are hidden/truncated |
| Search inputs | Magnifying glass as field prefix is a universal signifier |
| CTA buttons with `+` | `+ New Session` — the plus clarifies intent, not decoration |
| Overflow menu `···` | Standard affordance, universally understood |
| Board / List view toggle | Icons distinguish rendering modes at a glance (grid vs. list) |
| Row-level action buttons | Trash, edit, link — pure action, no label needed |
| Filter button on Board pages | `⫶ Filters` — single button where an icon helps identify the function |

### ⚠️ Use selectively

| Context | Guidance |
|---|---|
| Status indicators in dense lists | Colored dot is enough; icon may over-signal |
| Selection mode bulk actions | Done (✓), Delete (🗑) benefit from icons — Clear (×) is borderline |
| Empty states | One illustrative icon is fine; don't use Heroicons as illustration |
| Detail panel section headers | Only if the section is icon-keyed elsewhere (e.g., rail matches panel) |

### ❌ Do not use icons

| Context | Why it's wrong |
|---|---|
| Page title in top bar | `📋 Tasks` — the page name is already self-labeling; icon adds noise |
| Filter pills | `⏱ Working`, `✓ Done` — text scanning is faster; icons add visual weight |
| Sort options | `Newest`, `Oldest`, `Priority` are self-explanatory text |
| Tab navigation (generally) | 2–3 tabs: text is cleaner. **Exception:** Detail/Workspace 6-tab header (Messages/Tasks/Commits/Notes/Context/Settings) — icons justified as scan anchors for frequent switching in dense workspace context. Icon assignments: chat-bubble-left-ellipsis, clipboard-document-list, code-bracket, document-text, information-circle, cog-6-tooth. |
| Every metadata item | `status icon + tag icon + user icon + clock icon` per row is too heavy |

### The underlying principle

EITS is a dense, information-rich tool for technical users. It needs **structure clarity** more than visual richness. Icons that reduce text scanning (rail, search, actions) earn their place. Icons that add visual rhythm without reducing cognitive load (every pill, every tab, every metadata field) do not.

When in doubt: if a senior designer would call it "decorative," remove it.

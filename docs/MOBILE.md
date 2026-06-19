# Mobile Layout Standards

Standards for mobile-responsive UI in the EITS web app. Established during mobile layout fixes (PRs #264-#276, commits ab17275-a21fdd0).

---

## Touch Target Sizing

All interactive elements (buttons, links, nav items, filter controls) must meet a minimum touch target of **44px** in both height and width.

### Rules

- Apply `min-h-[44px]` to all tappable elements
- Icon-only buttons also need `min-w-[44px]`
- Combined pattern for icon buttons: `min-h-[44px] min-w-[44px] flex items-center justify-center`

### Examples

**Sidebar nav links** (`lib/eye_in_the_sky_web/components/sidebar.ex`):
```heex
<.link class="flex items-center gap-2 text-sm transition-colors min-h-[44px]" ...>
```

**Sidebar icon buttons** (theme toggle, settings, collapse):
```heex
<button class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full hover:bg-base-content/10 transition-colors">
```

**Drawer close buttons** (`task_detail_drawer.ex`, `job_form_drawer.ex`):
```heex
<button class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md ...">
```

**Mobile bottom nav tabs** (`notifications.ex`):
```heex
<button class="flex flex-col items-center justify-center rounded-lg py-2 min-h-[44px] text-[11px] font-medium ...">
```

**Filter button groups** (`notifications.ex`):
```heex
<button class="join-item btn btn-sm min-h-[44px] ...">
```

**Notes star/kebab actions** (`notes_list.ex`):
```heex
<button class="flex items-center justify-center min-h-[44px] min-w-[44px] px-1 py-1 rounded transition-colors ...">
```

**Quick-create dialog close buttons** (`quick_create_dialogs/*.ex`):
```heex
<button class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]" aria-label="Close">
```

**Notes action buttons** (`notes.ex`):
```heex
<button class="flex items-center gap-1.5 px-3 py-1.5 min-h-[44px] rounded-lg text-xs font-medium ...">
  <.icon ... /> Action Label
</button>
```

---

## Form Input Sizing

All text input fields and textareas must use **`text-base`** (16px) to prevent iOS Safari auto-zoom on focus. This is critical for mobile UX.

### Rules

- Replace `text-sm` / `text-xs` with `text-base` on all text, email, password, search, and textarea inputs
- Apply to both custom input components and inline `<input>` / `<textarea>` elements
- Update `core_components.ex` defaults to include `text-base` (already done)

### Why

iOS Safari auto-zooms input fields when the font size is less than 16px. This causes a jarring visual jump and breaks the user's scroll position. Using `text-base` prevents this behavior.

### Examples

**Input fields** (`core_components.ex`):
```heex
<input type={@type} class="input input-bordered text-base ..." />
<textarea class="textarea textarea-bordered text-base ..."></textarea>
```

**Search fields**:
```heex
<input type="search" placeholder="Search..." class="input input-sm text-base ..." />
```

**Form components**:
```heex
<input type="email" class="input text-base ..." />
<input type="password" class="input text-base ..." />
```

---

## Modal Safe-Area Padding

Modals and bottom sheets that can be dismissed or contain interactive elements near the bottom must account for the iPhone home indicator (safe-area-inset-bottom).

### Pattern

Add `pb-[env(safe-area-inset-bottom)]` to modal content containers:

```heex
<div class="modal-box pb-[env(safe-area-inset-bottom)] ...">
  <!-- modal content -->
</div>
```

### Examples

**Command palette modal** (`command_palette.ex`):
```heex
<div class="modal-box pb-[env(safe-area-inset-bottom)] max-w-lg ...">
```

**Filter sheet** (`filter_sheet.ex`):
```heex
<div class="modal-box pb-[env(safe-area-inset-bottom)] ...">
```

### Key points

- Prevents content from being hidden behind the home indicator on notched iPhones
- Only needed for modals/sheets that extend near the bottom of the viewport
- Use alongside sticky header offsets for full-screen modals

---

## Sticky Header Offsets

Mobile has a 3rem header plus safe-area insets. Desktop uses a different (typically larger) header. Sticky elements must account for both.

### Pattern

Use `calc()` with `env(safe-area-inset-top)` for mobile, and a separate `md:` breakpoint value for desktop:

```
sticky top-[calc(3rem+env(safe-area-inset-top))] md:top-16
```

### Real examples

**Filter bars** (`agent_list.ex`, `project_sessions_filters.ex`):
```heex
<div class="sticky top-[calc(3rem+env(safe-area-inset-top))] md:top-16 z-10 bg-base-100/85 backdrop-blur-md ...">
```

**Kanban toolbar** (`kanban_toolbar.ex`):
```heex
<div class="sticky top-[calc(3rem+env(safe-area-inset-top))] md:top-0 z-10 bg-base-100 ...">
```

**DM mobile header** (`dm_page.ex`):
```heex
<div class="md:hidden sticky top-0 z-30 ... pt-[env(safe-area-inset-top)] h-[calc(3rem+env(safe-area-inset-top))] ...">
```

### Key points

- Mobile header height: `3rem` + `env(safe-area-inset-top)`
- Desktop header height: typically `top-16` (4rem) or `top-20` (5rem) depending on context
- Always use `z-10` or higher so sticky elements stay above scrolling content
- Add `bg-base-100/85 backdrop-blur-md` for a frosted-glass effect on filter bars

---

## Viewport Minimum Width

The app targets a minimum viewport width of **320px** (iPhone SE / smallest common mobile). All layouts must remain usable at this width.

### Rules

- No fixed-width containers wider than 320px on mobile
- Use `w-full` with `max-w-sm` (24rem / 384px) for drawers so they scale down
- Filter groups should use `flex-wrap` to stack on narrow screens
- Toolbar items use `btn-sm` sizing on mobile

---

## Overflow Handling

Prevent horizontal scrolling on narrow viewports.

### Rules

- Sidebar nav uses `overflow-x-hidden` to clip any text overflow:
  ```heex
  <nav class="flex-1 overflow-y-auto overflow-x-hidden ...">
  ```
- Use `truncate` on text that could exceed container width (session names, long titles)
- Drawers use `w-full max-w-sm` to stay within viewport bounds
- Filter bars that might overflow use `flex-wrap` instead of horizontal scroll

### Anti-patterns to avoid

- `overflow-x-auto` on mobile nav (causes accidental horizontal scroll)
- Fixed pixel widths on any container visible at mobile breakpoints
- Long unbroken strings without `truncate` or `break-words`

---

## Accessibility

All touch targets should include `focus-visible` rings for keyboard navigation:

```
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-inset
```

This was applied across mobile bottom nav tabs and interactive elements during the mobile fixes.

---

## Standardized Responsive Patterns

This section documents shared responsive UI patterns that are consistently applied across overview/project screens.

### Action Bars

Action bars (bulk action controls, header button groups) must wrap on mobile to prevent overflow.

**Pattern:**
```heex
<div class="flex flex-wrap items-center gap-3 p-3 sm:p-4 bg-base-100 border border-base-300 rounded-lg">
  <span class="text-sm font-medium">Content</span>
  <div class="flex flex-wrap gap-2 ml-auto">
    <button class="btn btn-sm btn-outline">Action 1</button>
    <button class="btn btn-sm btn-outline">Action 2</button>
  </div>
</div>
```

**Rules:**
- Add `flex-wrap` to all action bars so buttons stack on mobile
- Use `gap-3` for spacing between content areas
- Use `gap-2` for button groups
- Use `ml-auto` on the button group div to right-align actions
- Padding: `p-3 sm:p-4 lg:p-6` for adaptive spacing across breakpoints

**Examples:**
- Bulk action bar in jobs table (`jobs_table.ex`)
- Bulk selection bar in agent list (`agent_list.ex`)
- Overview header with action buttons (`jobs_page.ex`)

### Search and Filter Rows

Search inputs and filter dropdowns must remain responsive and avoid overflow.

**Pattern:**
```heex
<form phx-change="filter" class="flex flex-wrap gap-2 my-4">
  <input
    type="text"
    name="search"
    class="input input-bordered input-sm flex-1 min-w-[200px] text-base min-h-[44px]"
    placeholder="Search…"
  />
  <select name="filter" class="select select-bordered select-sm min-h-[44px]">
    <option>Filter</option>
  </select>
</form>
```

**Rules:**
- Use `flex flex-wrap gap-2` on the form container
- Search inputs use `flex-1 min-w-[200px]` for responsive width
- Dropdowns maintain their natural width with `min-h-[44px]`
- All inputs use `text-base` to prevent iOS auto-zoom
- Controls stack on mobile (<sm) and wrap as needed

**Examples:**
- Jobs page filter toolbar (`jobs_page.ex`)
- Agent list search toolbar (`agent_list.ex`)

### Table Overflow Handling

Tables must be wrapped in `overflow-x-auto` on mobile to prevent content from breaking the layout.

**Pattern:**
```heex
<div class="overflow-x-auto">
  <table class="table table-sm">
    <!-- table content -->
  </table>
</div>
```

**Rules:**
- All data tables must have an `overflow-x-auto` wrapper div
- Wrapper allows horizontal scroll on small screens without breaking the layout
- Hidden on desktop if a separate mobile card layout exists using `hidden md:block`

**Examples:**
- Jobs table (`jobs_table.ex`)
- Config browser file listing (`config_browser.ex`)
- Agent schedule cron reference (`agent_schedule_form.ex`)

### Adaptive Padding

Container padding adjusts across breakpoints for consistent spacing.

**Pattern:**
```heex
<div class="p-3 sm:p-4 lg:p-6">
  <!-- content -->
</div>
```

**Rules:**
- Mobile (default): `p-3` (12px)
- Small screens (sm): `p-4` (16px)
- Large screens (lg): `p-6` (24px)
- Apply to: action bars, cards, filter containers, drawers
- Consistency: use the same pattern across similar components

**Examples:**
- Action bars with adaptive padding
- Filter sheet containers
- Drawer content areas

---

## Reference Commits

| PR | Scope |
|----|-------|
| #264 | Sidebar nav + theme toggle touch targets |
| #265 | Session metadata flex-wrap, filter tabs, config browser height |
| #266 | DM mobile header focus-visible rings |
| #267 | Kanban context menu touch, completion toggle |
| #268 | Task drawers w-full, close button tap area |
| #269 | Context tab collapse, job form drawer close button |
| #270 | Notifications filter btn-sm + flex-wrap, notes toolbar layout |
| #271 | Kanban toolbar sticky offset, settings theme button sizing |
| #273 | Task detail drawer close min-h-[44px], new agent drawer w-full |
| #274 | Sidebar nav min-h-[44px] on all touch targets |
| #275 | Sticky offsets for mobile header |
| #276 | Touch targets in notifications and notes_list |

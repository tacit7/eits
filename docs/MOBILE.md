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

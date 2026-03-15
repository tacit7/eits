# Teams Page Mobile Audit — Design Spec

**Date:** 2026-03-15
**File:** `lib/eye_in_the_sky_web_web/live/team_live/index.ex`

## Problem

The teams page uses a fixed two-panel desktop layout that breaks on mobile:
- `w-72` sidebar + detail panel side-by-side leaves ~100px for content on small screens
- `grid-cols-4` stats row is too cramped on mobile
- Hover-only interactions (`opacity-0 group-hover:opacity-100`) are inaccessible on touch devices

## Approach

Option B: LiveView `mobile_view` assign. On mobile, show only one panel at a time. Desktop always shows both panels. No JS required — pure LiveView state + Tailwind responsive classes.

## State Changes

Add one new assign to `mount/3`:

```elixir
|> assign(:mobile_view, :list)
```

Type: `:list | :detail`

## Event Handler Changes

`select_team` — additionally sets `mobile_view: :detail`:
```elixir
{:noreply, socket
 |> assign(:selected_team_id, team_id)
 |> assign(:selected_team, team)
 |> assign(:mobile_view, :detail)}
```

`close_team` — additionally sets `mobile_view: :list`:
```elixir
{:noreply, socket
 |> assign(:selected_team_id, nil)
 |> assign(:selected_team, nil)
 |> assign(:mobile_view, :list)}
```

## Template Changes

### Outer container

```heex
# Before
<div class="flex h-full gap-0">

# After
<div class="flex h-full gap-0 flex-col sm:flex-row">
```

### Sidebar (team list panel)

```heex
# Before
<div class="w-72 border-r border-base-300 flex flex-col shrink-0">

# After
<div class={[
  "border-r border-base-300 flex flex-col w-full sm:w-72 sm:shrink-0",
  @mobile_view == :detail && "hidden sm:flex"
]}>
```

### Detail panel

```heex
# Before
<div class="flex-1 overflow-y-auto min-w-0">

# After
<div class={[
  "flex-1 overflow-y-auto min-w-0 w-full",
  @mobile_view == :list && "hidden sm:block"
]}>
```

### Back button — inside detail panel, before `team_detail` component

```heex
<button
  class="sm:hidden flex items-center gap-2 px-4 py-3 text-sm text-base-content/60 border-b border-base-300 w-full hover:bg-base-200"
  phx-click="close_team"
>
  <.icon name="hero-arrow-left" class="w-4 h-4" />
  Teams
</button>
```

Only rendered when `@selected_team` is not nil.

### Stats grid

```heex
# Before
<div class="grid grid-cols-4 gap-3">

# After
<div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
```

### Session link (member row)

```heex
# Before
class="opacity-0 group-hover:opacity-100 flex items-center ..."

# After
class="sm:opacity-0 sm:group-hover:opacity-100 flex items-center ..."
```

### Assign task dropdown (unowned tasks)

```heex
# Before
class="opacity-0 group-hover:opacity-100 text-[10px] ..."

# After
class="sm:opacity-0 sm:group-hover:opacity-100 text-[10px] ..."
```

### Detail section padding

```heex
# Before
<div class="p-6 max-w-4xl space-y-6">

# After
<div class="p-4 sm:p-6 max-w-4xl space-y-6">
```

## Breakpoint

All mobile changes apply below Tailwind's `sm` breakpoint (640px). Desktop layout is unchanged.

## Out of Scope

- No changes to data loading, PubSub, or team/member logic
- No changes to existing desktop layout or styling
- No JS hooks required

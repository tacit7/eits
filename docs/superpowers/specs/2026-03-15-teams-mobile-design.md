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

**`select_team`** — only new line is `|> assign(:mobile_view, :detail)`. All other logic is unchanged:

```elixir
@impl true
def handle_event("select_team", %{"id" => id}, socket) do
  team_id = String.to_integer(id)
  team = Teams.get_team!(team_id) |> load_team_detail()
  {:noreply, socket
   |> assign(:selected_team_id, team_id)
   |> assign(:selected_team, team)
   |> assign(:mobile_view, :detail)}
end
```

**`close_team`** — only new line is `|> assign(:mobile_view, :list)`. All other logic is unchanged:

```elixir
@impl true
def handle_event("close_team", _params, socket) do
  {:noreply, socket
   |> assign(:selected_team_id, nil)
   |> assign(:selected_team, nil)
   |> assign(:mobile_view, :list)}
end
```

**`maybe_refresh_selected_team/1`** — replace the entire non-nil function clause (the second clause). The nil function clause is left as-is. Only the `nil ->` arm of the `case` inside the non-nil clause changes — add `|> assign(:mobile_view, :list)`:

```elixir
# Leave this clause unchanged:
defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: nil}} = socket), do: socket

# Replace this entire clause with:
defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: id}} = socket) do
  case Teams.get_team(id) do
    nil ->
      socket
      |> assign(:selected_team_id, nil)
      |> assign(:selected_team, nil)
      |> assign(:mobile_view, :list)
    team ->
      assign(socket, :selected_team, load_team_detail(team))
  end
end
```

This prevents the mobile detail view from getting stuck blank when a team is deleted via PubSub.

## Template Changes

### Outer container

```heex
<%!-- Before --%>
<div class="flex h-full gap-0">

<%!-- After --%>
<div class="flex h-full gap-0 flex-col sm:flex-row">
```

Note: `h-full flex-col` works correctly here because the list panel has its own internal
`flex flex-col` layout with `flex-1 overflow-y-auto` on its scroll child. The detail panel
already uses `flex-1 overflow-y-auto`. Both rely on `h-full` resolving to a concrete height
from the parent. Verify that the parent DOM chain (LiveView layout root) already propagates
a fixed height — if it does not, both panels may collapse on mobile. Check `app.html.heex`
and any wrapping layout components.

### Sidebar (team list panel)

Change the outer `<div>` of the team list sidebar:

```heex
<%!-- Before --%>
<div class="w-72 border-r border-base-300 flex flex-col shrink-0">

<%!-- After --%>
<div class={[
  "border-r border-base-300 flex flex-col w-full sm:w-72 sm:shrink-0",
  @mobile_view == :detail && "hidden sm:flex"
]}>
```

### Detail panel + back button

This change is in `render/1`. The back button must live here because `@mobile_view`
is in scope in `render/1` but not inside the `team_detail/1` private function component.

Replace the detail panel `<div>` and its contents:

```heex
<%!-- Before --%>
<div class="flex-1 overflow-y-auto min-w-0">
  <%= if @selected_team do %>
    <.team_detail team={@selected_team} />
  <% else %>
    <%!-- empty state --%>
  <% end %>
</div>

<%!-- After --%>
<div class={[
  "flex-1 overflow-y-auto min-w-0 w-full",
  @mobile_view == :list && "hidden sm:block"
]}>
  <%= if @mobile_view == :detail do %>
    <button
      class="sm:hidden flex items-center gap-2 px-4 py-3 text-sm text-base-content/60 border-b border-base-300 w-full hover:bg-base-200"
      phx-click="close_team"
    >
      <.icon name="hero-arrow-left" class="w-4 h-4" />
      Teams
    </button>
  <% end %>
  <%= if @selected_team do %>
    <.team_detail team={@selected_team} />
  <% else %>
    <%!-- preserve existing empty state markup exactly as-is — do not remove it --%>
  <% end %>
</div>
```

### Team name header row

Inside `team_detail/1`, the `<div>` wrapping the `h1` and status badge uses `flex items-center gap-3`.
On mobile a long team name causes the h1 to push the badge off-screen. Fix with `flex-wrap`:

```heex
<%!-- Before --%>
<div class="flex items-center gap-3 mb-1">

<%!-- After --%>
<div class="flex items-center flex-wrap gap-3 mb-1">
```

### Stats grid

Inside `team_detail/1` private function (`defp team_detail(assigns)`):

```heex
<%!-- Before --%>
<div class="grid grid-cols-4 gap-3">

<%!-- After --%>
<div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
```

### Session link (member row)

In the member row loop inside `team_detail/1`, the `<.link>` element's `class` attribute.
Change only the first two tokens, leaving the rest intact. The result is that the link is
**always visible on mobile** (removing the opacity-0 default), and only hidden-until-hover
on desktop (sm:). This is intentional — hover is not available on touch devices.

The member row will not overflow on narrow screens: the link has `shrink-0` and the info
div has `flex-1 min-w-0` with `truncate` on the name, so the layout degrades gracefully.

```
<%!-- Before --%>
opacity-0 group-hover:opacity-100 flex items-center gap-1 text-[10px] font-mono text-base-content/40 bg-base-content/5 px-2 py-1 rounded hover:text-base-content/60 transition-all shrink-0

<%!-- After --%>
sm:opacity-0 sm:group-hover:opacity-100 flex items-center gap-1 text-[10px] font-mono text-base-content/40 bg-base-content/5 px-2 py-1 rounded hover:text-base-content/60 transition-all shrink-0
```

### Assign task dropdown (unowned tasks)

The `<select>` element's `class` attribute inside `team_detail/1`.
Change only the first two tokens. Same intent as the session link: **always visible on mobile**,
hidden-until-hover on desktop.

```
<%!-- Before --%>
opacity-0 group-hover:opacity-100 text-[10px] bg-base-300 border-0 rounded px-1.5 py-0.5 text-base-content/60 cursor-pointer focus:outline-none transition-opacity

<%!-- After --%>
sm:opacity-0 sm:group-hover:opacity-100 text-[10px] bg-base-300 border-0 rounded px-1.5 py-0.5 text-base-content/60 cursor-pointer focus:outline-none transition-opacity
```

### Detail section padding

Inside `team_detail/1`:

```heex
<%!-- Before --%>
<div class="p-6 max-w-4xl space-y-6">

<%!-- After --%>
<div class="p-4 sm:p-6 max-w-4xl space-y-6">
```

## Breakpoint

All mobile changes apply below Tailwind's `sm` breakpoint (640px). Desktop layout is unchanged.

## Out of Scope

- No changes to data loading, PubSub, or team/member logic
- No changes to existing desktop layout or styling
- No JS hooks required
- The `toggle_archived` button label bug (both branches render `"archived"`) is pre-existing; fixing it is out of scope for this mobile audit

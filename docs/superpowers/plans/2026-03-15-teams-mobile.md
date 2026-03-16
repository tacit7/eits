# Teams Page Mobile Audit Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the teams page usable on mobile by adding a `mobile_view` assign that switches between a full-screen list and full-screen detail view below the `sm` breakpoint.

**Architecture:** A single LiveView file is modified. State transitions are centralized in two private helpers (`show_team_detail/3`, `show_team_list/1`) so `mobile_view` never drifts from `selected_team`. Template changes use Tailwind responsive prefixes — no JS required.

**Tech Stack:** Elixir, Phoenix LiveView, Tailwind CSS, HEEx templates, ExUnit

---

## Files

| Action | File |
|--------|------|
| Modify | `lib/eye_in_the_sky_web_web/live/team_live/index.ex` |
| Create | `test/eye_in_the_sky_web_web/live/team_live_test.exs` |

---

## Chunk 1: Elixir logic — state helpers, mount assign, event handlers

### Task 1: Write failing LiveView tests for mobile state

**Files:**
- Create: `test/eye_in_the_sky_web_web/live/team_live_test.exs`

- [ ] **Step 1: Create the test file**

```elixir
defmodule EyeInTheSkyWebWeb.TeamLive.IndexTest do
  use EyeInTheSkyWebWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mobile_view assign" do
    test "mounts with mobile_view :list", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/teams")
      assert render(lv) =~ "Teams"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it passes baseline**

```bash
mix test test/eye_in_the_sky_web_web/live/team_live_test.exs
```

Expected: PASS

---

### Task 2: Add state transition helpers

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/team_live/index.ex`

- [ ] **Step 1: Add `show_team_detail/3` and `show_team_list/1` before `active_member_count/1`**

```elixir
defp show_team_detail(socket, team_id, team) do
  socket
  |> assign(:selected_team_id, team_id)
  |> assign(:selected_team, team)
  |> assign(:mobile_view, :detail)
end

defp show_team_list(socket) do
  socket
  |> assign(:selected_team_id, nil)
  |> assign(:selected_team, nil)
  |> assign(:mobile_view, :list)
end
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: clean compile

---

### Task 3: Add `mobile_view` to `mount/3`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/team_live/index.ex` (lines 12–27)

- [ ] **Step 1: Add `|> assign(:mobile_view, :list)` to mount return**

Find:
```elixir
    {:ok,
     socket
     |> assign(:page_title, "Teams")
     |> assign(:sidebar_tab, :teams)
     |> assign(:sidebar_project, nil)
     |> assign(:show_archived, false)
     |> assign(:teams, load_teams(false))
     |> assign(:selected_team_id, nil)
     |> assign(:selected_team, nil)}
```

Replace with:
```elixir
    {:ok,
     socket
     |> assign(:page_title, "Teams")
     |> assign(:sidebar_tab, :teams)
     |> assign(:sidebar_project, nil)
     |> assign(:show_archived, false)
     |> assign(:teams, load_teams(false))
     |> assign(:selected_team_id, nil)
     |> assign(:selected_team, nil)
     |> assign(:mobile_view, :list)}
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

---

### Task 4: Update event handlers to use helpers

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/team_live/index.ex` (lines 39–48)

- [ ] **Step 1: Replace `select_team` handler**

Find:
```elixir
  def handle_event("select_team", %{"id" => id}, socket) do
    team_id = String.to_integer(id)
    team = Teams.get_team!(team_id) |> load_team_detail()
    {:noreply, socket |> assign(:selected_team_id, team_id) |> assign(:selected_team, team)}
  end
```

Replace with:
```elixir
  def handle_event("select_team", %{"id" => id}, socket) do
    team_id = String.to_integer(id)
    team = Teams.get_team!(team_id) |> load_team_detail()
    {:noreply, show_team_detail(socket, team_id, team)}
  end
```

- [ ] **Step 2: Replace `close_team` handler**

Find:
```elixir
  def handle_event("close_team", _params, socket) do
    {:noreply, socket |> assign(:selected_team_id, nil) |> assign(:selected_team, nil)}
  end
```

Replace with:
```elixir
  def handle_event("close_team", _params, socket) do
    {:noreply, show_team_list(socket)}
  end
```

- [ ] **Step 3: Replace `maybe_refresh_selected_team/1` non-nil clause**

Find (the second clause only — leave the nil clause alone):
```elixir
  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: id}} = socket) do
    case Teams.get_team(id) do
      nil -> socket |> assign(:selected_team_id, nil) |> assign(:selected_team, nil)
      team -> assign(socket, :selected_team, load_team_detail(team))
    end
  end
```

Replace with:
```elixir
  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: id}} = socket) do
    case Teams.get_team(id) do
      nil -> show_team_list(socket)
      team -> assign(socket, :selected_team, load_team_detail(team))
    end
  end
```

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 5: Run tests**

```bash
mix test test/eye_in_the_sky_web_web/live/team_live_test.exs
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/team_live/index.ex \
        test/eye_in_the_sky_web_web/live/team_live_test.exs
git commit -m "feat: add mobile_view assign and state transition helpers to team_live"
```

---

## Chunk 2: Template changes

### Task 5: Outer container — `flex-col sm:flex-row`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/team_live/index.ex` (`render/1`, line 72)

- [ ] **Step 1: Update outer container class**

Find:
```heex
<div class="flex h-full gap-0">
```

Replace with:
```heex
<div class="flex h-full gap-0 flex-col sm:flex-row">
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

---

### Task 6: Sidebar panel — full height + responsive visibility

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/team_live/index.ex` (line 74)

Note: `flex-1 sm:flex-none` is required so the list panel fills the `flex-col` container's height on mobile. Without it, the panel collapses to content height and the inner `overflow-y-auto` scroll never activates.

- [ ] **Step 1: Update sidebar outer div**

Find:
```heex
<div class="w-72 border-r border-base-300 flex flex-col shrink-0">
```

Replace with:
```heex
<div class={[
  "border-r border-base-300 flex flex-col flex-1 sm:flex-none w-full sm:w-72 sm:shrink-0",
  @mobile_view == :detail && "hidden sm:flex"
]}>
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

---

### Task 7: Detail panel — visibility + back button

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/team_live/index.ex` (lines 154–172)

- [ ] **Step 1: Replace the entire detail panel div block**

Find:
```heex
      <%!-- Team detail panel --%>
      <div class="flex-1 overflow-y-auto min-w-0">
        <%= if @selected_team do %>
          <.team_detail team={@selected_team} />
        <% else %>
          <div class="flex items-center justify-center h-full">
            <div class="text-center space-y-3">
              <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mx-auto">
                <.icon name="hero-user-group" class="w-8 h-8 text-base-content/20" />
              </div>
              <div>
                <p class="text-sm font-medium text-base-content/30">No team selected</p>
                <p class="text-xs text-base-content/20 mt-1">Choose a team from the list</p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
```

Replace with:
```heex
      <%!-- Team detail panel --%>
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
          <div class="flex items-center justify-center h-full">
            <div class="text-center space-y-3">
              <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mx-auto">
                <.icon name="hero-user-group" class="w-8 h-8 text-base-content/20" />
              </div>
              <div>
                <p class="text-sm font-medium text-base-content/30">No team selected</p>
                <p class="text-xs text-base-content/20 mt-1">Choose a team from the list</p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

---

### Task 8: `team_detail/1` — five mobile fixes

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/team_live/index.ex` (`defp team_detail`, lines 182–375)

All changes below are inside `defp team_detail(assigns)`.

- [ ] **Step 1: Detail section padding**

Find:
```heex
<div class="p-6 max-w-4xl space-y-6">
```

Replace with:
```heex
<div class="p-4 sm:p-6 max-w-4xl space-y-6">
```

- [ ] **Step 2: Team name header row — allow badge to wrap**

Find:
```heex
<div class="flex items-center gap-3 mb-1">
```

Replace with:
```heex
<div class="flex items-center flex-wrap gap-3 mb-1">
```

- [ ] **Step 3: Stats grid — 2 columns on mobile**

Find:
```heex
<div class="grid grid-cols-4 gap-3">
```

Replace with:
```heex
<div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
```

- [ ] **Step 4: Session link — always visible on mobile**

Find the `<.link>` in the member row whose class starts with `opacity-0 group-hover:opacity-100 flex items-center gap-1`:

```
class="opacity-0 group-hover:opacity-100 flex items-center gap-1 text-[10px] font-mono text-base-content/40 bg-base-content/5 px-2 py-1 rounded hover:text-base-content/60 transition-all shrink-0"
```

Change only the first two tokens:
```
class="sm:opacity-0 sm:group-hover:opacity-100 flex items-center gap-1 text-[10px] font-mono text-base-content/40 bg-base-content/5 px-2 py-1 rounded hover:text-base-content/60 transition-all shrink-0"
```

- [ ] **Step 5: Assign task dropdown — always visible on mobile**

Find the `<select>` in the unowned tasks section whose class starts with `opacity-0 group-hover:opacity-100 text-[10px]`:

```
class="opacity-0 group-hover:opacity-100 text-[10px] bg-base-300 border-0 rounded px-1.5 py-0.5 text-base-content/60 cursor-pointer focus:outline-none transition-opacity"
```

Change only the first two tokens:
```
class="sm:opacity-0 sm:group-hover:opacity-100 text-[10px] bg-base-300 border-0 rounded px-1.5 py-0.5 text-base-content/60 cursor-pointer focus:outline-none transition-opacity"
```

- [ ] **Step 6: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Run all tests**

```bash
mix test
```

Expected: all pass

- [ ] **Step 8: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/team_live/index.ex
git commit -m "feat: mobile-responsive template for teams page"
```

---

## Post-Implementation Checklist

Verify in browser DevTools at 375px width:

- [ ] Initial load — list fills screen, no horizontal scroll
- [ ] Tap a team — detail view, back button at top
- [ ] Tap back — returns to list
- [ ] Stats grid: 2 columns
- [ ] Session UUID link visible without hover
- [ ] Assign dropdown visible without hover
- [ ] Long team name wraps, badge stays
- [ ] List scrolls with many teams
- [ ] Detail scrolls with many members/tasks
- [ ] Desktop (1024px+) — two-panel layout unchanged

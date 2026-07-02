# Teams Page: Bulk Select/Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the same bulk multi-select and delete behavior to the Teams page that already exists on the Sessions page.

**Architecture:** Add MapSet-based selection state to the Teams LiveView, render a selection toolbar and per-row checkboxes in the template, and wire event handlers (`toggle_select`, `toggle_select_all`, `delete_selected`) that call a new `Teams.batch_delete_teams/1` context function (soft-delete / archive). No new module files needed — everything fits in the existing `teams.ex` LiveView and `teams.ex` context.

**Tech Stack:** Elixir/Phoenix LiveView, HEEx, DaisyUI/Tailwind, existing `square_checkbox` component and `selection_toolbar` from `project_sessions_table.ex`.

## Global Constraints

- Teams delete = **soft delete** (archive): set `status: "archived"` and `archived_at`, do NOT hard-delete rows.
- Do not change the existing per-row hover trash-icon delete — keep it alongside the new bulk path.
- No `indeterminate_ids` needed — teams have no parent/child tree hierarchy.
- Use `MapSet` of string IDs (match the session pattern: `to_string(team.id)`).
- Stream IDs are `"teams-#{team.id}"` (LiveView stream convention for the `:teams` stream).
- `mix compile --warnings-as-errors` must pass before commit.

---

## File Map

| File | Change |
|------|--------|
| `lib/eye_in_the_sky/teams.ex` | Add `batch_delete_teams/1` |
| `lib/eye_in_the_sky_web/live/project_live/teams.ex` | Add selection assigns, 3 new event handlers, update template |

---

### Task 1: Add `Teams.batch_delete_teams/1` context function

**Files:**
- Modify: `lib/eye_in_the_sky/teams.ex:111-119`

**Interfaces:**
- Produces: `Teams.batch_delete_teams(ids :: [integer()]) :: {non_neg_integer(), [Team.t()]}` — archives each team and broadcasts `:team_deleted`; returns `{count, archived_teams}`.

- [ ] **Step 1: Read the file to find the insertion point**

Open `lib/eye_in_the_sky/teams.ex`, locate line 111 (`delete_team/1`). The new function goes immediately after it (after the closing `end` of `delete_team`).

- [ ] **Step 2: Add `batch_delete_teams/1` after `delete_team/1`**

```elixir
@doc "Archive multiple teams by ID list. Calls delete_team/1 for each and returns {count, archived}."
def batch_delete_teams(ids) when is_list(ids) do
  teams = Enum.map(ids, &get_team!/1)

  archived =
    Enum.filter(teams, fn team ->
      case delete_team(team) do
        {:ok, _} -> true
        _ -> false
      end
    end)

  {length(archived), archived}
end
```

- [ ] **Step 3: Verify compilation**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix compile --warnings-as-errors
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky/teams.ex
git commit -m "feat: add Teams.batch_delete_teams/1 for bulk archive"
```

---

### Task 2: Add selection state to the Teams LiveView mount

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/teams.ex` (mount function, roughly lines 11–70)

**Interfaces:**
- Produces assigns: `selected_ids :: MapSet.t()`, `select_mode :: boolean()`

- [ ] **Step 1: Read current mount in `teams.ex`**

Open `lib/eye_in_the_sky_web/live/project_live/teams.ex`. Find the `mount/3` function. Identify where `socket` is returned (the final `{:ok, socket}` or `assign(socket, ...)` chain).

- [ ] **Step 2: Add selection assigns to the mount return**

Append to the assign chain inside `mount/3`:

```elixir
|> assign(:selected_ids, MapSet.new())
|> assign(:select_mode, false)
```

The mount return should look like:

```elixir
{:ok,
 socket
 |> assign(:teams, teams)   # existing
 # ... other existing assigns ...
 |> assign(:selected_ids, MapSet.new())
 |> assign(:select_mode, false)
 |> stream(:teams, teams)}
```

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/teams.ex
git commit -m "feat: add selection state assigns to teams LiveView mount"
```

---

### Task 3: Add `toggle_select` event handler

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/teams.ex` (add after existing `handle_event` clauses, before render)

**Interfaces:**
- Consumes: `phx-click="toggle_select"` with `phx-value-id={team.id}` from the template (added in Task 5)
- Produces: updated `selected_ids` MapSet, updated `select_mode`

- [ ] **Step 1: Add `toggle_select` handler**

Find where the `handle_event` clauses are defined in `teams.ex` (around lines 158–210). Add after the existing `delete_team` handler and before any `render/1` function:

```elixir
def handle_event("toggle_select", %{"id" => id}, socket) do
  id = to_string(id)
  selected_ids = socket.assigns.selected_ids

  selected_ids =
    if MapSet.member?(selected_ids, id) do
      MapSet.delete(selected_ids, id)
    else
      MapSet.put(selected_ids, id)
    end

  select_mode = MapSet.size(selected_ids) > 0

  {:noreply,
   socket
   |> assign(:selected_ids, selected_ids)
   |> assign(:select_mode, select_mode)}
end
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/teams.ex
git commit -m "feat: add toggle_select event handler to teams LiveView"
```

---

### Task 4: Add `toggle_select_all` and `delete_selected` event handlers

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/teams.ex`

**Interfaces:**
- `toggle_select_all` — selects all visible teams (from stream, inferred from `socket.assigns.teams`) or deselects all
- `delete_selected` — calls `Teams.batch_delete_teams/1` with selected IDs as integers, clears selection state

- [ ] **Step 1: Add `toggle_select_all` handler**

Immediately after the `toggle_select` handler added in Task 3:

```elixir
def handle_event("toggle_select_all", _params, socket) do
  all_ids =
    socket.assigns.teams
    |> Enum.map(&to_string(&1.id))
    |> MapSet.new()

  {selected_ids, select_mode} =
    if MapSet.size(socket.assigns.selected_ids) == MapSet.size(all_ids) do
      {MapSet.new(), false}
    else
      {all_ids, true}
    end

  {:noreply,
   socket
   |> assign(:selected_ids, selected_ids)
   |> assign(:select_mode, select_mode)}
end
```

> Note: `socket.assigns.teams` holds the full list set during mount/`handle_params`. This is the list used to populate the stream. If the page has filtering, this should reflect the filtered list.

- [ ] **Step 2: Add `delete_selected` handler**

```elixir
def handle_event("delete_selected", _params, socket) do
  ids =
    socket.assigns.selected_ids
    |> MapSet.to_list()
    |> Enum.map(&String.to_integer/1)

  Teams.batch_delete_teams(ids)

  {:noreply,
   socket
   |> assign(:selected_ids, MapSet.new())
   |> assign(:select_mode, false)}
end
```

> The PubSub broadcast from `delete_team/1` (already wired in `batch_delete_teams/1`) will handle removing each team from the stream via the existing `handle_info/2` `:team_deleted` clause.

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/teams.ex
git commit -m "feat: add toggle_select_all and delete_selected handlers to teams LiveView"
```

---

### Task 5: Add checkbox to each team row in the template

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/teams.ex` (render function, team row section ~lines 253–304)

**Interfaces:**
- Consumes: `@selected_ids`, `@select_mode` assigns
- Produces: `phx-click="toggle_select"` with `phx-value-id={team.id}` per row

- [ ] **Step 1: Read the current team row template**

Open `lib/eye_in_the_sky_web/live/project_live/teams.ex` and find the `<div id={...} phx-update="stream">` block (around line 254). Find the individual team row `<div>` — likely `class="group flex items-center ..."`.

- [ ] **Step 2: Wrap the row div with a relative container and add a checkbox**

The row currently starts something like:

```heex
<div id={id} class="group flex items-center gap-3 ...">
```

Change to:

```heex
<div id={id} class="group relative flex items-center gap-3 ...">
  <%# Checkbox — always rendered, hidden unless select_mode or hovered %>
  <div
    class={[
      "absolute left-0 top-0 bottom-0 flex items-center pl-2 z-10 transition-opacity",
      if(@select_mode, do: "opacity-100", else: "opacity-0 group-hover:opacity-100")
    ]}
    phx-click="toggle_select"
    phx-value-id={team.id}
  >
    <.square_checkbox
      id={"team-checkbox-#{team.id}"}
      checked={MapSet.member?(@selected_ids, to_string(team.id))}
      aria-label={"Select team #{team.name}"}
    />
  </div>
  <%# Shift content right when select_mode active to make room for checkbox %>
  <div class={["flex items-center gap-3 w-full min-w-0", if(@select_mode, do: "pl-7", else: "")]}>
    <%# ... existing row content (status dot, name, count, description, delete button) ... %>
  </div>
</div>
```

> The `square_checkbox` component is defined in `CoreComponents` and already used by the sessions page. Check for it with `grep -r "square_checkbox" lib/eye_in_the_sky_web/core_components.ex`.

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Manually test in browser**

Start the dev server:
```bash
mix phx.server
```

Navigate to `/projects/1/teams`. Hover over a team row — checkbox should appear. Click it — row should become selected (checkbox checked). Click again — deselected.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/teams.ex
git commit -m "feat: add per-row selection checkbox to teams page"
```

---

### Task 6: Add selection toolbar to the template

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/teams.ex` (render function, above the stream list)

**Interfaces:**
- Consumes: `@selected_ids`, `@select_mode`, `@teams` assigns
- Produces: toolbar with select-all checkbox + count + archive/delete button, visible when `@select_mode`

- [ ] **Step 1: Locate where to insert the toolbar**

In `render/1`, find the section just above the `<div phx-update="stream">` list (around line 253). Insert the toolbar between the filter controls (if any) and the stream div.

- [ ] **Step 2: Add toolbar HEEx**

```heex
<%# Selection toolbar — shown when one or more teams selected %>
<%= if @select_mode do %>
  <div class="flex items-center gap-2 px-4 py-2 bg-base-200 rounded-lg mb-2">
    <%# Select-all checkbox %>
    <div phx-click="toggle_select_all" class="cursor-pointer flex items-center">
      <.square_checkbox
        id="teams-select-all"
        checked={MapSet.size(@selected_ids) == length(@teams) && length(@teams) > 0}
        aria-label="Select all teams"
      />
    </div>

    <span class="text-sm text-base-content/70 flex-1">
      {MapSet.size(@selected_ids)} selected
    </span>

    <button
      phx-click="delete_selected"
      class="btn btn-ghost btn-sm text-error/70 hover:text-error hover:bg-error/10 gap-1"
    >
      <.icon name="hero-trash-mini" class="size-3.5" /> Archive
    </button>
  </div>
<% end %>
```

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Manual test**

In the browser:
1. Click a team row checkbox → toolbar appears with "1 selected" and "Archive" button.
2. Click the select-all checkbox → all rows checked, count updates.
3. Click "Archive" → selected teams disappear from list (soft-deleted via PubSub broadcast).
4. Confirm teams are archived in the DB:
   ```bash
   psql eits_dev -c "SELECT id, name, status, archived_at FROM teams WHERE status='archived' ORDER BY archived_at DESC LIMIT 5;"
   ```
5. Deselect all → toolbar disappears.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/teams.ex
git commit -m "feat: add selection toolbar to teams page with select-all and archive action"
```

---

## Self-Review

### Spec Coverage
- [x] Per-row checkbox — Task 5
- [x] Select all — Task 6 toolbar + Task 4 handler
- [x] Count display — Task 6 toolbar
- [x] Delete/archive button — Task 6 toolbar + Task 4 handler
- [x] Bulk archive context function — Task 1
- [x] Selection state — Task 2
- [x] Individual toggle — Task 3
- [x] Clear state after delete — Task 4

### Placeholder Scan
None — all code blocks are complete.

### Type Consistency
- `selected_ids` is `MapSet.t()` of string IDs throughout.
- `Teams.batch_delete_teams/1` takes `[integer()]` — conversion from strings to integers is done in `delete_selected` handler before the call.
- `toggle_select_all` reads from `socket.assigns.teams` (list) — consistent with what mount assigns as `:teams`.

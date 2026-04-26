# Sessions Bulk Selection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the sessions bulk-select UX: selected-row highlight, bulk archive, parent indeterminate state, filter-resilient selection, and shift-click range.

**Architecture:** Selection state lives in the LiveView socket (`selected_ids` MapSet of string IDs, `select_mode` boolean). A dedicated `Selection` helper module centralizes all MapSet logic so `Actions` and `Loader` share the same computation without duplication. Each task is self-contained and commits cleanly.

**Tech Stack:** Elixir/Phoenix LiveView, HEEx, Tailwind/DaisyUI, vanilla JS LiveView hooks

---

## What Already Exists (Do Not Rebuild)

- Hover-reveal checkbox per row (`session_card.ex`)
- `select_mode` / `selected_ids` state (`State.init`)
- Select-all checkbox with `IndeterminateCheckbox` hook on select-all
- Bulk delete with confirm modal (`agent_list.ex`, `actions.ex`)
- `toggle_select`, `toggle_select_all`, `exit_select_mode`, `enter_select_mode` handlers
- `depths` map for parent/child depth tracking
- `IndeterminateCheckbox` hook in `assets/js/hooks/indeterminate_checkbox.js`

---

## Selection State Invariants

These invariants must hold across all tasks. Every function that touches selection state must respect them.

- `selected_ids` is always a `MapSet` of **string** session IDs. LiveView event params arrive as strings; normalize everything with `to_string/1` on entry.
- `select_mode` becomes `true` when selection is non-empty and `false` when selection is empty or explicitly exited. It does not stay true after the last row is deselected.
- Bulk actions (archive, delete) apply to **all** IDs in `selected_ids`, including IDs not visible under the current filter.
- `toggle_select_all` applies **only** to currently visible sessions and **preserves** any off-screen selected IDs.
- `off_screen_selected_count` is derived: `size(selected_ids - visible_agent_ids)`.
- `indeterminate_ids` is derived: parent IDs where some (not all) **currently visible** direct children are selected. Limited to visible children — if children are filtered out, indeterminate state may not reflect the full tree.
- Parent checkbox state: checked when the parent session ID itself is in `selected_ids`; indeterminate when at least one but not all visible direct children are selected and the parent itself is not selected. Selecting a parent does not select its children; selecting children does not auto-select the parent.
- After any bulk operation, clear `select_mode`, `selected_ids`, `indeterminate_ids`, and `off_screen_selected_count` atomically via `Selection.clear_selection/1`.
- **Bulk mutation handlers must scope selected IDs to the current project before archiving or deleting.** Client-provided or socket-stored IDs are not trusted by themselves. The route being project-scoped does not protect against a malicious or stale client event payload.

---

## File Map

| File | Change |
|------|--------|
| Create: `lib/.../live/project_live/sessions/selection.ex` | New module: all selection-derived computation and socket helpers |
| Modify: `lib/.../components/session_card.ex` | Selected-row bg tint; `indeterminate` attr on `session_row`; `checkbox_area` attr on checkbox |
| Modify: `lib/.../components/core_components.ex` | Add `id`, `indeterminate`, `checkbox_area` attrs to `square_checkbox`; two `:if` branches for input to avoid `phx-hook={nil}` |
| Modify: `lib/.../components/project_sessions_table.ex` | Archive button in `selection_toolbar`; off-screen count display; `data-row-id` on stream items; `ShiftSelect` wrapper div; `select_all_checkbox_state` wiring |
| Modify: `lib/.../components/project_sessions_page.ex` | Thread `off_screen_selected_count`, `indeterminate_ids` (Task 3); thread `show_archive_confirm` in Task 4 only |
| Modify: `lib/.../components/agent_list.ex` | Add `archive_confirm_modal/1` component |
| Modify: `lib/.../live/project_live/sessions/actions.ex` | Fix `toggle_select/2` (select_mode = size > 0); fix `toggle_select_all` (visible-only); add archive handlers; add `select_range`; use `Selection` throughout |
| Modify: `lib/.../live/project_live/sessions/filter_handlers.ex` | Remove selection clear from `filter_session/2` |
| Modify: `lib/.../live/project_live/sessions/loader.ex` | Call `recompute_selection_metadata/1` after `:agents` is assigned |
| Modify: `lib/.../live/project_live/sessions/state.ex` | Add `off_screen_selected_count`, `indeterminate_ids` assigns (Task 3); add `show_archive_confirm` (Task 4) |
| Modify: `lib/.../live/project_live/sessions.ex` | Add `handle_event` entries for new events |
| Create: `assets/js/hooks/shift_select.js` | Single capture-phase listener; `stopImmediatePropagation` on shift path |
| Modify: `assets/js/app.js` | Register `ShiftSelect` hook |
| Modify: `test/.../sessions_test.exs` | Tagged tests for all new behaviour |

---

## Task 1: Selection Helper Module

**Files:**
- Create: `lib/eye_in_the_sky_web/live/project_live/sessions/selection.ex`

Centralizes all selection-derived MapSet logic. Both `Actions` and `Loader` depend on it so the same computation never gets duplicated. Also owns `clear_selection/1` for atomically resetting all selection assigns.

- [ ] **Step 1: Write the module**

```elixir
# lib/eye_in_the_sky_web/live/project_live/sessions/selection.ex
defmodule EyeInTheSkyWeb.ProjectLive.Sessions.Selection do
  @moduledoc """
  Helpers for deriving and applying session selection state.

  Pure derivation functions (normalize_id, off_screen_count, etc.) take plain data.
  `clear_selection/1` takes a socket and is the canonical way to reset all selection assigns.

  All IDs are normalized to strings because LiveView event params arrive as strings.
  """

  import Phoenix.LiveView, only: [assign: 3]

  @doc "Normalize any session ID to a string."
  def normalize_id(id), do: to_string(id)

  @doc "Build a MapSet of string IDs from the current visible session/agent rows."
  def ids_from_agents(agents) do
    MapSet.new(agents, &normalize_id(&1.id))
  end

  @doc "Number of selected IDs not in the current visible agents list."
  def off_screen_count(selected_ids, agents) do
    visible_ids = ids_from_agents(agents)
    MapSet.size(MapSet.difference(selected_ids, visible_ids))
  end

  @doc """
  Set of parent session IDs (as strings) where some — but not all — currently
  visible direct children are selected.

  Limitation: only considers children present in `agents` (the visible/loaded list).
  If children are filtered out, their absence is not reflected here.
  """
  def compute_indeterminate_ids(selected_ids, agents) do
    children_by_parent =
      agents
      |> Enum.reject(&is_nil(&1.parent_session_id))
      |> Enum.group_by(&normalize_id(&1.parent_session_id))

    Enum.reduce(children_by_parent, MapSet.new(), fn {parent_id, children}, acc ->
      child_ids = MapSet.new(children, &normalize_id(&1.id))
      selected_count = MapSet.size(MapSet.intersection(selected_ids, child_ids))

      cond do
        # Parent is selected — show checked, not indeterminate
        MapSet.member?(selected_ids, parent_id) -> acc
        selected_count == 0 -> acc
        selected_count == MapSet.size(child_ids) -> acc
        true -> MapSet.put(acc, parent_id)
      end
    end)
  end

  @doc """
  Toggle all visible sessions: add all visible IDs if any are unselected; remove
  all visible IDs if all are already selected. Off-screen selected IDs are preserved.
  """
  def select_all_visible(selected_ids, agents) do
    visible_ids = ids_from_agents(agents)

    all_visible_selected? =
      MapSet.size(visible_ids) > 0 and MapSet.subset?(visible_ids, selected_ids)

    if all_visible_selected? do
      MapSet.difference(selected_ids, visible_ids)
    else
      MapSet.union(selected_ids, visible_ids)
    end
  end

  @doc """
  Returns `{checked?, indeterminate?}` for the select-all toolbar checkbox.

  Reflects only currently visible rows. Off-screen selected rows are shown via the
  count text "(N not visible)" — not via the select-all checkbox state.

  - `{true, false}` — all visible rows selected.
  - `{false, true}` — some visible rows selected.
  - `{false, false}` — no visible rows selected.
  """
  def select_all_checkbox_state(selected_ids, agents) do
    visible_ids = ids_from_agents(agents)
    visible_count = MapSet.size(visible_ids)
    visible_selected = MapSet.size(MapSet.intersection(selected_ids, visible_ids))

    cond do
      visible_count == 0 -> {false, false}
      visible_selected == visible_count -> {true, false}
      visible_selected > 0 -> {false, true}
      true -> {false, false}
    end
  end

  @doc """
  Resets all selection assigns to cleared state. Use after bulk operations or
  when the user explicitly exits select mode.
  """
  def clear_selection(socket) do
    socket
    |> assign(:select_mode, false)
    |> assign(:selected_ids, MapSet.new())
    |> assign(:indeterminate_ids, MapSet.new())
    |> assign(:off_screen_selected_count, 0)
  end
end
```

- [ ] **Step 2: Compile check**

```bash
mix compile --warnings-as-errors 2>&1 | tail -10
```

Expected: 0 errors, 0 warnings

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/sessions/selection.ex
git commit -m "feat: add Selection helper module for bulk-select state derivation"
```

---

## Task 2: Selected Row Visual Highlight

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/session_card.ex`
- Modify: `test/eye_in_the_sky_web/live/project_live/sessions_test.exs`

Add `bg-primary/5 ring-1 ring-primary/20` to selected rows. Status border is preserved.

- [ ] **Step 1: Write the failing test**

```elixir
# test/eye_in_the_sky_web/live/project_live/sessions_test.exs
describe "Bulk selection — row highlight" do
  @tag :bulk_select
  @tag :bulk_select_row_highlight
  test "selected session row has bg-primary/5 on the row element", %{conn: conn, project: project} do
    {:ok, session} =
      EyeInTheSky.Sessions.create_session(%{
        name: "Highlight test",
        project_id: project.id,
        status: "idle"
      })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(session.id)})

    html = render(view)
    assert html =~ ~r/id="session-row-#{session.id}"[^>]*bg-primary\/5/
  end
end
```

- [ ] **Step 2: Run test, verify FAIL**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select_row_highlight 2>&1 | tail -20
```

Expected: FAIL — pattern not found in row element

- [ ] **Step 3: Update the outer row div in `session_row`**

In `lib/eye_in_the_sky_web/components/session_card.ex`, find:

```elixir
    <div
      id={"session-row-#{@session.id}"}
      class={"relative group/row bg-base-100 border-l-2 pl-2 " <> @status_border}
    >
```

Replace with:

```elixir
    <div
      id={"session-row-#{@session.id}"}
      class={[
        "relative group/row border-l-2 pl-2",
        if(@selected, do: "bg-primary/5 ring-1 ring-primary/20 ring-inset rounded-lg", else: "bg-base-100"),
        @status_border
      ]}
    >
```

- [ ] **Step 4: Run test, verify PASS**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select_row_highlight 2>&1 | tail -10
```

- [ ] **Step 5: Compile check**

```bash
MIX_ENV=test mix compile --warnings-as-errors 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web/components/session_card.ex \
        test/eye_in_the_sky_web/live/project_live/sessions_test.exs
git commit -m "feat: selected session row gets bg-primary/5 tint and ring accent"
```

---

## Task 3: Filter-Resilient Selection and Fixed Select-All Semantics

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions/filter_handlers.ex`
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions/loader.ex`
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex`
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions/state.ex`
- Modify: `lib/eye_in_the_sky_web/components/project_sessions_table.ex`
- Modify: `lib/eye_in_the_sky_web/components/project_sessions_page.ex`
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions.ex`

This is the foundational task. Everything else depends on it being correct.

- [ ] **Step 0: Verify actual status and filter values**

```bash
grep -R "session_filter\|filter_session\|status ==\|\"working\"\|\"running\"\|\"active\"\|\"idle\"" \
  lib/eye_in_the_sky_web/live/project_live/sessions \
  lib/eye_in_the_sky_web/components/project_sessions_table.ex | head -20
```

Use the actual status strings the app uses. The tests below use `status: "idle"` and `filter: "active"` with `status: "working"` as the active session. **Replace these with real values if they differ.**

> **`render_click` vs `render_hook`:** Before writing tests, run:
> ```bash
> grep -R "render_click\|render_hook" test/eye_in_the_sky_web/live/project_live/sessions_test.exs test/eye_in_the_sky_web/live/ | head -30
> ```
> Follow the existing style exactly. The **preferred** style is DOM-driven:
> ```elixir
> view |> element("[phx-click='toggle_select'][phx-value-id='#{id}']") |> render_click()
> ```
> The shorthand `render_click(view, "event", params)` may or may not be available depending on Phoenix LiveView version and test imports. Test snippets in this plan use the shorthand as placeholder — **replace with the DOM-driven style or the project's confirmed style**. Reserve `render_hook(view, "event", params)` strictly for hook-pushed events like `select_range`.

> **Test tags:** Tag every bulk-select test with both `@tag :bulk_select` (broad, run the whole suite) and a specific tag (e.g., `@tag :bulk_select_filter_resilience`). Run the full suite with `--only bulk_select`; run individual tests with the specific tag.

> **`@agents` source of truth — VERIFY BEFORE IMPLEMENTING:** `recompute_selection_metadata/1` uses `socket.assigns.agents`. This **must** be the complete pre-stream list that drives `@streams.session_list` — not a paginated slice or post-transform subset. If the stream is built from a different list (e.g. a windowed/paginated slice), use that list instead. If `socket.assigns.agents` is a slice, off-screen count will under-count and indeterminate logic will be wrong for any session whose children fall outside the slice. Run this before implementing:
> ```bash
> grep -n "assign.*:agents\|stream_insert\|apply_agent_view\|session_list" lib/eye_in_the_sky_web/live/project_live/sessions/loader.ex
> ```
> Confirm which list is the source and use it consistently in `recompute_selection_metadata/1`.

- [ ] **Step 1: Write failing tests**

```elixir
describe "Bulk selection — filter resilience" do
  @tag :bulk_select
  @tag :bulk_select_filter_resilience
  test "selection survives a filter change", %{conn: conn, project: project} do
    {:ok, s1} =
      EyeInTheSky.Sessions.create_session(%{name: "Idle one", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(s1.id)})
    assert has_element?(view, "[data-role='selection-count'][data-selected-count='1']")

    view |> render_click("filter_session", %{"filter" => "active"})

    assert has_element?(view, "[data-role='selection-count'][data-selected-count='1']")
    assert has_element?(view, "[data-role='selection-count'][data-offscreen-count='1']")
  end

  @tag :bulk_select
  @tag :bulk_select_select_all_visible
  test "select_all_visible preserves off-screen selected sessions", %{conn: conn, project: project} do
    {:ok, idle} =
      EyeInTheSky.Sessions.create_session(%{name: "Idle", project_id: project.id, status: "idle"})

    {:ok, _active} =
      EyeInTheSky.Sessions.create_session(%{name: "Active", project_id: project.id, status: "working"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(idle.id)})
    view |> render_click("filter_session", %{"filter" => "active"})
    view |> render_click("toggle_select_all", %{})

    assert has_element?(view, "[data-role='selection-count'][data-selected-count='2']")
    assert has_element?(view, "[data-role='selection-count'][data-offscreen-count='1']")
  end

  @tag :bulk_select
  @tag :bulk_select_toggle_all_deselect
  test "select_all_visible toggles off visible sessions on second call", %{conn: conn, project: project} do
    {:ok, _s1} =
      EyeInTheSky.Sessions.create_session(%{name: "A", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select_all", %{})
    view |> render_click("toggle_select_all", %{})

    refute has_element?(view, "[data-role='selection-count']")
  end

  @tag :bulk_select
  @tag :bulk_select_toggle_all_preserves_offscreen
  test "select_all_visible toggled again removes only visible sessions, preserves off-screen", %{conn: conn, project: project} do
    {:ok, idle} =
      EyeInTheSky.Sessions.create_session(%{name: "Idle", project_id: project.id, status: "idle"})

    {:ok, _active} =
      EyeInTheSky.Sessions.create_session(%{name: "Active", project_id: project.id, status: "working"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    # Select idle off-screen, filter to active
    view |> render_click("toggle_select", %{"id" => to_string(idle.id)})
    view |> render_click("filter_session", %{"filter" => "active"})

    # Select-all adds the active session; total 2 selected
    view |> render_click("toggle_select_all", %{})
    assert has_element?(view, "[data-role='selection-count'][data-selected-count='2']")

    # Select-all again removes only visible (active); idle off-screen survives
    view |> render_click("toggle_select_all", %{})
    assert has_element?(view, "[data-role='selection-count'][data-selected-count='1']")
    assert has_element?(view, "[data-role='selection-count'][data-offscreen-count='1']")
  end

  @tag :bulk_select
  @tag :bulk_select_exit_clears
  test "exit_select_mode clears all selected sessions including off-screen", %{conn: conn, project: project} do
    {:ok, session} =
      EyeInTheSky.Sessions.create_session(%{name: "Idle", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(session.id)})
    view |> render_click("filter_session", %{"filter" => "active"})
    view |> render_click("exit_select_mode", %{})

    refute has_element?(view, "[data-role='selection-count']")
  end
end
```

- [ ] **Step 2: Run tests, verify FAIL**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select 2>&1 | tail -20
```

- [ ] **Step 3: Add new assigns to `State.init`**

In `lib/eye_in_the_sky_web/live/project_live/sessions/state.ex`, add after `:select_mode`:

```elixir
    |> assign(:off_screen_selected_count, 0)
    |> assign(:indeterminate_ids, MapSet.new())
```

> `show_archive_confirm` is added in Task 4, not here. Only add the two assigns above now.

- [ ] **Step 4: Remove selection clear from `filter_session/2`**

In `lib/eye_in_the_sky_web/live/project_live/sessions/filter_handlers.ex`, the current code clears `selected_ids` and `select_mode`. Replace the entire function with:

```elixir
  def filter_session(%{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:session_filter, filter)
      |> Loader.load_agents()

    {:noreply, socket}
  end
```

- [ ] **Step 5: Add `recompute_selection_metadata/1` to `Loader`**

In `lib/eye_in_the_sky_web/live/project_live/sessions/loader.ex`, add the alias and function:

```elixir
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Selection

  defp recompute_selection_metadata(socket) do
    # Guard against missing assigns on first mount before State.init runs
    selected = Map.get(socket.assigns, :selected_ids, MapSet.new())
    agents = Map.get(socket.assigns, :agents, [])

    socket
    |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, agents))
    |> assign(:indeterminate_ids, Selection.compute_indeterminate_ids(selected, agents))
  end
```

**Where to call it:** Call `|> recompute_selection_metadata()` as the **last pipe** in `load_agents/1`, after `:agents` has been assigned to the socket. If `load_agents/1` delegates to `apply_agent_view/2`, call it only at the end of `load_agents/1` — not inside both functions — to avoid double computation.

Check the current `Loader` structure:

```bash
grep -n "def load_agents\|def apply_agent_view\|assign.*:agents" lib/eye_in_the_sky_web/live/project_live/sessions/loader.ex
```

Add the call after whichever function is the final exit point that sets `:agents`.

- [ ] **Step 6: Fix `toggle_select_all/2` to preserve off-screen selection**

In `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex`, add alias at top:

```elixir
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Selection
```

Replace `toggle_select_all/2`:

```elixir
  def toggle_select_all(_params, socket) do
    selected = Selection.select_all_visible(socket.assigns.selected_ids, socket.assigns.agents)

    socket =
      socket
      |> assign(:selected_ids, selected)
      |> assign(:select_mode, MapSet.size(selected) > 0)
      |> assign(:indeterminate_ids, Selection.compute_indeterminate_ids(selected, socket.assigns.agents))
      |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, socket.assigns.agents))

    {:noreply, socket}
  end
```

- [ ] **Step 7: Fix `toggle_select/2` — normalize ID and set `select_mode` based on count**

```elixir
  def toggle_select(%{"id" => raw_id}, socket) do
    id = Selection.normalize_id(raw_id)

    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    socket =
      socket
      |> assign(:selected_ids, selected)
      |> assign(:select_mode, MapSet.size(selected) > 0)
      |> assign(:indeterminate_ids, Selection.compute_indeterminate_ids(selected, socket.assigns.agents))
      |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, socket.assigns.agents))

    {:noreply, socket}
  end
```

- [ ] **Step 8: Fix `exit_select_mode/2` to use `Selection.clear_selection/1`**

```elixir
  def exit_select_mode(_params, socket) do
    {:noreply, Selection.clear_selection(socket)}
  end
```

- [ ] **Step 9: Add `off_screen_selected_count` display to `selection_toolbar`**

In `lib/eye_in_the_sky_web/components/project_sessions_table.ex`, add attr:

```elixir
  attr :off_screen_selected_count, :integer, default: 0
```

Update the count span inside `selection_toolbar/1`. Add stable `data-role` and count attrs for reliable test assertions — text can change without breaking tests:

```heex
          <span
            data-role="selection-count"
            data-selected-count={MapSet.size(@selected_ids)}
            data-offscreen-count={@off_screen_selected_count}
            class="text-[11px] text-base-content/50 font-medium"
          >
            {MapSet.size(@selected_ids)} selected
            <%= if @off_screen_selected_count > 0 do %>
              <span class="text-base-content/30">({@off_screen_selected_count} not visible)</span>
            <% end %>
          </span>
```

> Wrap this span in `<%= if MapSet.size(@selected_ids) > 0 do %>`. Use selected count — not `select_mode` — as the render condition; count is the source of truth. The `data-role='selection-count'` element must be absent when nothing is selected, because tests assert `refute has_element?(view, "[data-role='selection-count']")` to verify cleared state.

- [ ] **Step 10: Thread new assigns through `project_sessions_page.ex`**

Add attrs (do **not** add `show_archive_confirm` yet — that assign doesn't exist until Task 4):

```elixir
  attr :off_screen_selected_count, :integer, default: 0
  attr :indeterminate_ids, :any, default: MapSet.new()
```

Pass to `<.selection_toolbar>`:

```heex
        <.selection_toolbar
          select_mode={@select_mode}
          agents={@agents}
          selected_ids={@selected_ids}
          off_screen_selected_count={@off_screen_selected_count}
        />
```

- [ ] **Step 11: Pass new assigns from `sessions.ex` render**

Add to the `<.page>` call (again, **not** `show_archive_confirm` until Task 4):

```heex
      off_screen_selected_count={@off_screen_selected_count}
      indeterminate_ids={@indeterminate_ids}
```

- [ ] **Step 12: Run tests, verify PASS**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select 2>&1 | tail -10
```

(Runs all `@tag :bulk_select` tests added so far. After Task 3 only the filter-resilience group will match.)

- [ ] **Step 13: Compile check**

```bash
MIX_ENV=test mix compile --warnings-as-errors 2>&1 | tail -10
```

- [ ] **Step 14: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/sessions/filter_handlers.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions/loader.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions/state.ex \
        lib/eye_in_the_sky_web/components/project_sessions_table.ex \
        lib/eye_in_the_sky_web/components/project_sessions_page.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions.ex \
        test/eye_in_the_sky_web/live/project_live/sessions_test.exs
git commit -m "feat: selection persists across filters; select-all is visible-only; off-screen count shown"
```

---

## Task 4: Bulk Archive

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex`
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions.ex`
- Modify: `lib/eye_in_the_sky_web/components/project_sessions_table.ex`
- Modify: `lib/eye_in_the_sky_web/components/agent_list.ex`
- Modify: `lib/eye_in_the_sky_web/components/project_sessions_page.ex`

**Security requirement:** Bulk archive must scope to the current project. `selected_ids` is socket state, but a malicious or stale client event can inject arbitrary IDs. Archive only sessions that belong to `socket.assigns.project.id`.

- [ ] **Step 0: Add `show_archive_confirm` to `State.init`**

In `lib/eye_in_the_sky_web/live/project_live/sessions/state.ex`, add after the assigns from Task 3:

```elixir
    |> assign(:show_archive_confirm, false)
```

- [ ] **Step 1: Verify the `Sessions` context API and check for project-scoped fetch**

```bash
grep -n "def get_session\|def archive_session\|def get_project_session\|def session_belongs" \
  lib/eye_in_the_sky/sessions.ex
```

Also inspect the `archive_session/1` implementation:

```bash
grep -n "def archive_session" -A 10 lib/eye_in_the_sky/sessions.ex
```

And confirm the archive marker field on the schema:

```bash
grep -n "field :archived_at\|field :status\|:archived" lib/eye_in_the_sky/sessions/session.ex 2>/dev/null || \
  grep -rn "field :archived_at\|:archived" lib/eye_in_the_sky/
```

Note:
- Does `get_session/1` return `{:ok, session} | {:error, :not_found}` or does it raise?
- Does `archive_session/1` return `{:ok, session}`, a bare session, or another tuple?
- Is the archive marker `archived_at` (datetime) or `status == "archived"` or something else?
- Does a project-scoped variant exist (e.g. `get_project_session/2`)?

**Implement exactly one `fetch_project_session/2` helper matching the actual API. Do not leave both branches in the file.**

If no project-scoped variant exists, add a private helper in `actions.ex`. Both branches normalize the ID on entry:

```elixir
  # Fetches a session only if it belongs to the given project.
  # Returns {:ok, session} | {:error, :not_found}
  defp fetch_project_session(project_id, raw_id) do
    id = Selection.normalize_id(raw_id)
    with {:ok, session} <- Sessions.get_session(id) do
      if session.project_id == project_id, do: {:ok, session}, else: {:error, :not_found}
    end
  end
```

If `get_session/1` raises instead of returning `{:ok, _}`, use:

```elixir
  defp fetch_project_session(project_id, raw_id) do
    id = Selection.normalize_id(raw_id)
    session = Sessions.get_session!(id)
    if session.project_id == project_id, do: {:ok, session}, else: {:error, :not_found}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
```

Use whichever branch matches Step 1 output. The rest of the handler code below uses `fetch_project_session/2`.

- [ ] **Step 2: Write the failing tests**

Add a private test helper based on the archive marker you confirmed in Step 1. If the marker is `archived_at`:

```elixir
defp assert_archived(session_id) do
  assert EyeInTheSky.Sessions.get_session!(session_id).archived_at
end
```

If it's `status == "archived"`:

```elixir
defp assert_archived(session_id) do
  assert EyeInTheSky.Sessions.get_session!(session_id).status == "archived"
end
```

Use `assert_archived/1` in all archive tests. Only one line needs changing if the schema differs.

```elixir
describe "Bulk selection — archive" do
  @tag :bulk_select
  @tag :bulk_select_archive_basic
  test "archive_selected archives all selected sessions", %{conn: conn, project: project} do
    {:ok, s1} =
      EyeInTheSky.Sessions.create_session(%{name: "A", project_id: project.id, status: "idle"})
    {:ok, s2} =
      EyeInTheSky.Sessions.create_session(%{name: "B", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(s1.id)})
    view |> render_click("toggle_select", %{"id" => to_string(s2.id)})
    view |> render_click("confirm_archive_selected", %{})
    view |> render_click("archive_selected", %{})

    assert render(view) =~ "Archived 2 sessions"
    assert_archived(s1.id)
    assert_archived(s2.id)
    refute has_element?(view, "[data-role='selection-count']")
  end

  @tag :bulk_select
  @tag :bulk_select_archive_offscreen
  test "archive_selected archives off-screen selected sessions", %{conn: conn, project: project} do
    {:ok, idle} =
      EyeInTheSky.Sessions.create_session(%{name: "Idle", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(idle.id)})
    view |> render_click("filter_session", %{"filter" => "active"})
    view |> render_click("confirm_archive_selected", %{})
    view |> render_click("archive_selected", %{})

    assert render(view) =~ "Archived 1 session"
    assert_archived(idle.id)
  end

  @tag :bulk_select
  @tag :bulk_select_archive_button
  test "archive button is visible in bulk action bar when sessions are selected", %{conn: conn, project: project} do
    {:ok, session} =
      EyeInTheSky.Sessions.create_session(%{name: "T", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(session.id)})

    assert has_element?(view, "button[phx-click='confirm_archive_selected']", "Archive")
  end
end
```

- [ ] **Step 3: Run tests, verify FAIL**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select 2>&1 | tail -20
```

- [ ] **Step 4: Add handlers to `actions.ex`**

First, check whether `Sessions.archive_session/1` broadcasts a PubSub event:

```bash
grep -n "broadcast\|PubSub\|Events\." lib/eye_in_the_sky/sessions.ex | grep -i archive
```

If it **does** broadcast (e.g. a session-updated or session-archived event), and `handle_info` in `sessions.ex` already calls `Loader.load_agents()` in response, **remove the explicit `Loader.load_agents()` call from `archive_selected/2`** — let the PubSub path handle the refresh. Keeping both causes a visible double-reload of the stream.

If it does **not** broadcast, keep `Loader.load_agents()` as written below.

Confirm top-of-file has (add if missing):

```elixir
  alias EyeInTheSky.Sessions
  require Logger
```

Then add:

```elixir
  def confirm_archive_selected(_params, socket) do
    {:noreply, assign(socket, :show_archive_confirm, true)}
  end

  def cancel_archive_selected(_params, socket) do
    {:noreply, assign(socket, :show_archive_confirm, false)}
  end

  def archive_selected(_params, socket) do
    # Guard against stale/empty state
    if MapSet.size(socket.assigns.selected_ids) == 0 do
      {:noreply, assign(socket, :show_archive_confirm, false)}
    else
      project_id = socket.assigns.project.id

      results =
        Enum.map(socket.assigns.selected_ids, fn id ->
          with {:ok, session} <- fetch_project_session(project_id, id),
               :ok <- archive_project_session(session) do
            :ok
          else
            {:error, :not_found} -> :error
            {:error, reason} ->
              Logger.warning("bulk archive: failed for session #{id}: #{inspect(reason)}")
              :error
          end
        end)

      archived = Enum.count(results, &(&1 == :ok))
      failed = length(results) - archived

      {flash_level, flash_msg} =
        cond do
          archived > 0 and failed > 0 ->
            {:info, "Archived #{archived} #{pluralize_session(archived)}; #{failed} could not be archived"}
          archived > 0 ->
            {:info, "Archived #{archived} #{pluralize_session(archived)}"}
          true ->
            {:error, "Could not archive #{failed} #{pluralize_session(failed)}"}
        end

      socket =
        socket
        |> assign(:show_archive_confirm, false)
        |> Selection.clear_selection()
        |> Loader.load_agents()
        |> put_flash(flash_level, flash_msg)

      {:noreply, socket}
    end
  end

  defp pluralize_session(count), do: if(count == 1, do: "session", else: "sessions")

  # Wraps archive_session/1 to normalize its return shape.
  # Handles {:ok, session}, bare struct, or error tuple.
  # Inspect Sessions.archive_session/1 in Step 1 and simplify if the return is always {:ok, _}.
  defp archive_project_session(session) do
    case Sessions.archive_session(session) do
      {:ok, _} -> :ok
      %{__struct__: _} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_archive_result, other}}
    end
  end
```

- [ ] **Step 5: Wire events in `sessions.ex`**

```elixir
  def handle_event("confirm_archive_selected", params, socket),
    do: Actions.confirm_archive_selected(params, socket)

  def handle_event("cancel_archive_selected", params, socket),
    do: Actions.cancel_archive_selected(params, socket)

  def handle_event("archive_selected", params, socket),
    do: Actions.archive_selected(params, socket)
```

- [ ] **Step 6: Verify icon name, then add Archive button to `selection_toolbar`**

```bash
grep -r "archive-box" lib/ assets/ 2>/dev/null | head -5
```

If `hero-archive-box-mini` is found, use it. Otherwise use `hero-archive-box`.

Inside the `<%= if MapSet.size(@selected_ids) > 0 do %>` block in `selection_toolbar/1`, after the delete button:

```heex
          <button
            phx-click="confirm_archive_selected"
            class="btn btn-ghost btn-xs text-warning/70 hover:text-warning hover:bg-warning/10 gap-1 min-h-[44px] min-w-[44px]"
          >
            <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" /> Archive
          </button>
```

- [ ] **Step 7: Add `archive_confirm_modal/1` to `agent_list.ex`**

```elixir
  attr :show_archive_confirm, :boolean, required: true
  attr :selected_ids, :any, required: true

  def archive_confirm_modal(assigns) do
    ~H"""
    <dialog
      id="archive-confirm-modal"
      class={"modal modal-bottom sm:modal-middle " <> if(@show_archive_confirm, do: "modal-open", else: "")}
    >
      <div class="modal-box w-full sm:max-w-sm pb-[env(safe-area-inset-bottom)]">
        <h3 class="text-lg font-bold">Archive sessions</h3>
        <p class="py-4 text-sm text-base-content/70">
          <% count = MapSet.size(@selected_ids) %>
          Archive {count} selected session{if count == 1, do: "", else: "s"}?
          Archived sessions can be unarchived later.
        </p>
        <div class="modal-action">
          <button phx-click="cancel_archive_selected" class="btn btn-sm btn-ghost min-h-[44px]">
            Cancel
          </button>
          <button phx-click="archive_selected" class="btn btn-sm btn-warning min-h-[44px]">
            Archive
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_archive_selected">close</button>
      </form>
    </dialog>
    """
  end
```

- [ ] **Step 8: Render the modal in `project_sessions_page.ex`**

First confirm the actual module name:

```bash
grep -n "defmodule .*AgentList" lib/eye_in_the_sky_web/components/agent_list.ex
```

Use the exact module name from that output in the import below.

Add the attr (now that `State.init` has it):

```elixir
  attr :show_archive_confirm, :boolean, default: false
```

Add import:

```elixir
  import EyeInTheSkyWeb.Components.AgentList, only: [archive_confirm_modal: 1]
```

Thread from `sessions.ex` `<.page>` call:

```heex
      show_archive_confirm={@show_archive_confirm}
```

Render after existing modals in `page/1`:

```heex
    <.archive_confirm_modal
      show_archive_confirm={@show_archive_confirm}
      selected_ids={@selected_ids}
    />
```

- [ ] **Step 9: Run tests, verify PASS**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select 2>&1 | tail -10
```

- [ ] **Step 10: Compile check**

```bash
MIX_ENV=test mix compile --warnings-as-errors 2>&1 | tail -10
```

- [ ] **Step 11: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/sessions/state.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions.ex \
        lib/eye_in_the_sky_web/components/project_sessions_table.ex \
        lib/eye_in_the_sky_web/components/project_sessions_page.ex \
        lib/eye_in_the_sky_web/components/agent_list.ex \
        test/eye_in_the_sky_web/live/project_live/sessions_test.exs
git commit -m "feat: bulk archive sessions with confirm modal; project-scoped"
```

---

## Task 5: Parent Row Indeterminate State + Select-All Indeterminate

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/core_components.ex`
- Modify: `lib/eye_in_the_sky_web/components/session_card.ex`
- Modify: `lib/eye_in_the_sky_web/components/project_sessions_table.ex`

`square_checkbox` gains optional `id`, `indeterminate`, and `checkbox_area` attrs. The `checkbox_area` attr adds `data-checkbox-area="true"` to the outer label — used by the shift-click hook in Task 6. Two `:if` branches on the input element avoid `phx-hook={nil}`.

Before writing the test, verify how child sessions are created and rendered in the app:

```bash
grep -R "parent_session_id" test/ lib/eye_in_the_sky_web/live/project_live lib/eye_in_the_sky_web/components | head -20
```

Use the same factory/setup pattern the existing tests use. Do not invent session data that the UI does not render.

- [ ] **Step 1: Write failing test**

```elixir
describe "Bulk selection — indeterminate state" do
  @tag :bulk_select
  @tag :bulk_select_parent_indeterminate
  test "parent checkbox has data-indeterminate=true when some children selected", %{conn: conn, project: project} do
    {:ok, parent} =
      EyeInTheSky.Sessions.create_session(%{name: "Parent", project_id: project.id, status: "idle"})

    {:ok, child1} =
      EyeInTheSky.Sessions.create_session(%{
        name: "Child 1", project_id: project.id, status: "idle", parent_session_id: parent.id
      })

    {:ok, _child2} =
      EyeInTheSky.Sessions.create_session(%{
        name: "Child 2", project_id: project.id, status: "idle", parent_session_id: parent.id
      })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(child1.id)})

    html = render(view)
    assert html =~ ~r/id="session-checkbox-#{parent.id}"[^>]*data-indeterminate="true"/
  end

  @tag :bulk_select
  @tag :bulk_select_all_indeterminate
  test "select-all checkbox is indeterminate when some visible sessions are selected", %{conn: conn, project: project} do
    {:ok, s1} =
      EyeInTheSky.Sessions.create_session(%{name: "A", project_id: project.id, status: "idle"})

    {:ok, _s2} =
      EyeInTheSky.Sessions.create_session(%{name: "B", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    view |> render_click("toggle_select", %{"id" => to_string(s1.id)})

    html = render(view)
    assert html =~ ~r/id="sessions-select-all-checkbox"[^>]*data-indeterminate="true"/
  end
end
```

- [ ] **Step 2: Run test, verify FAIL**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs \
  --only bulk_select_parent_indeterminate 2>&1 | tail -20
```

- [ ] **Step 3: Update `square_checkbox` in `core_components.ex`**

Use two `:if` branches on the input to avoid ever rendering `phx-hook={nil}`:

```elixir
  attr :id, :string, default: nil
  attr :checked, :boolean, required: true
  attr :indeterminate, :boolean, default: false
  attr :checkbox_area, :boolean, default: false
  attr :class, :string, default: ""
  attr :rest, :global

  def square_checkbox(assigns) do
    ~H"""
    <label
      data-checkbox-area={if @checkbox_area, do: "true", else: nil}
      class={"select-none flex items-center cursor-pointer " <> @class}
    >
      <%!-- With id: attach IndeterminateCheckbox hook so the native .indeterminate property stays in sync --%>
      <input
        :if={@id}
        id={@id}
        type="checkbox"
        class="sr-only"
        checked={@checked}
        data-indeterminate={to_string(@indeterminate)}
        phx-hook="IndeterminateCheckbox"
        {@rest}
      />
      <%!-- Without id: plain checkbox, no hook. Callers must not pass phx-hook in @rest
           to this branch — LiveView would attach the hook but fail to find the element by ID. --%>
      <input
        :if={!@id}
        type="checkbox"
        class="sr-only"
        checked={@checked}
        data-indeterminate={to_string(@indeterminate)}
        {@rest}
      />
      <div class={[
        "shrink-0 w-4 h-4 flex items-center justify-center border rounded transition-colors duration-100",
        cond do
          @indeterminate -> "bg-primary/30 border-primary/60"
          @checked -> "bg-primary border-primary"
          true -> "bg-base-100 border-base-content/20 hover:border-primary/40"
        end
      ]}>
        <%= cond do %>
          <% @indeterminate -> %>
            <div class="w-2 h-0.5 bg-primary rounded-full"></div>
          <% @checked -> %>
            <.icon name="hero-check-mini" class="w-2.5 h-2.5 text-primary-content" />
          <% true -> %>
        <% end %>
      </div>
    </label>
    """
  end
```

- [ ] **Step 4: Add `indeterminate` attr to `session_row` in `session_card.ex`**

```elixir
  attr :indeterminate, :boolean, default: false
```

Update the `<.square_checkbox>` call to pass `id`, `indeterminate`, and `checkbox_area`:

```heex
        <.square_checkbox
          id={"session-checkbox-#{@session.id}"}
          checked={@selected}
          indeterminate={@indeterminate}
          checkbox_area={true}
          phx-click="toggle_select"
          phx-value-id={@session.id}
          onclick="event.stopPropagation()"
          aria-label={"Select session #{@session.name || @session.id}"}
        />
```

> Note: `onclick="event.stopPropagation()"` prevents row navigation from firing when the checkbox is clicked. The shift-click hook in Task 6 uses capture phase, which runs before this stops propagation.

- [ ] **Step 5: Thread `indeterminate_ids` through `session_list` in `project_sessions_table.ex`**

Add attr:

```elixir
  attr :indeterminate_ids, :any, default: MapSet.new()
```

Pass to `<.session_row>` inside `session_list/1`:

```heex
              indeterminate={MapSet.member?(@indeterminate_ids, to_string(agent.id))}
```

- [ ] **Step 6: Update select-all checkbox in `selection_toolbar` to use `Selection.select_all_checkbox_state/2`**

Add alias at top of `project_sessions_table.ex`:

```elixir
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Selection
```

Replace the select-all checkbox in `selection_toolbar/1` with:

```heex
      <%
        {all_checked, some_checked} = Selection.select_all_checkbox_state(@selected_ids, @agents)
      %>
      <.square_checkbox
        id="sessions-select-all-checkbox"
        checked={all_checked}
        indeterminate={some_checked}
        phx-click="toggle_select_all"
        aria-label="Select all sessions"
      />
```

Remove any previous manual `checked`/`data-indeterminate` computation on this element.

- [ ] **Step 7: Pass `indeterminate_ids` from `project_sessions_page.ex` to `session_list`**

```heex
        <.session_list
          ...
          indeterminate_ids={@indeterminate_ids}
        />
```

- [ ] **Step 8: Run test, verify PASS**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs \
  --only bulk_select_parent_indeterminate 2>&1 | tail -10
```

- [ ] **Step 9: Compile check**

```bash
MIX_ENV=test mix compile --warnings-as-errors 2>&1 | tail -10
```

- [ ] **Step 10: Commit**

```bash
git add lib/eye_in_the_sky_web/components/core_components.ex \
        lib/eye_in_the_sky_web/components/session_card.ex \
        lib/eye_in_the_sky_web/components/project_sessions_table.ex \
        lib/eye_in_the_sky_web/components/project_sessions_page.ex \
        test/eye_in_the_sky_web/live/project_live/sessions_test.exs
git commit -m "feat: parent and select-all checkboxes show indeterminate state"
```

---

## Task 6: Shift-Click Range Selection

**Files:**
- Create: `assets/js/hooks/shift_select.js`
- Modify: `assets/js/app.js`
- Modify: `lib/eye_in_the_sky_web/components/project_sessions_table.ex`
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex`
- Modify: `lib/eye_in_the_sky_web/live/project_live/sessions.ex`

**Shift-click behavior:**
- Normal click toggles one row and sets the anchor.
- Shift-click selects the inclusive visible range between the anchor and target (union only; does not deselect ranges).
- If the first interaction is a shift-click (no prior anchor), no range is selected; that row becomes the anchor.
- Range uses current DOM order (visible rows after filter/sort).
- `ordered_ids` from the client are filtered server-side against visible agent IDs.

**Why capture phase:** The checkbox has `onclick="event.stopPropagation()"` to prevent row navigation. A bubble-phase wrapper listener would never see the click. Using `{ capture: true }` means the hook runs before that stop fires. A single capture handler tracks the anchor on normal clicks and handles ranges on shift-clicks — no separate bubble listener needed.

- [ ] **Step 1: Write failing test**

```elixir
describe "Bulk selection — shift-click range" do
  @tag :bulk_select
  @tag :bulk_select_range
  test "select_range selects all IDs between anchor and target", %{conn: conn, project: project} do
    sessions =
      for n <- 1..5 do
        {:ok, s} =
          EyeInTheSky.Sessions.create_session(%{
            name: "S#{n}", project_id: project.id, status: "idle"
          })
        s
      end

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    ids = Enum.map(sessions, &to_string(&1.id))

    view
    |> render_hook("select_range", %{
      "anchor_id" => Enum.at(ids, 0),
      "target_id" => Enum.at(ids, 2),
      "ordered_ids" => ids
    })

    assert has_element?(view, "[data-role='selection-count'][data-selected-count='3']")
  end

  @tag :bulk_select
  @tag :bulk_select_range_dom_wiring
  test "shift-select DOM hooks and data attrs are present", %{conn: conn, project: project} do
    {:ok, session} =
      EyeInTheSky.Sessions.create_session(%{name: "X", project_id: project.id, status: "idle"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

    assert has_element?(view, "#ps-list-shift-wrapper[phx-hook='ShiftSelect']")
    assert has_element?(view, "[data-row-id='#{session.id}']")
    # Checkboxes are hover-revealed via CSS; they exist in DOM but may be visually hidden.
    # If conditionally rendered, enter select mode first or assert after toggle_select.
    assert has_element?(view, "[data-checkbox-area='true']")
  end
end
```

- [ ] **Step 2: Run tests, verify FAIL**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select 2>&1 | tail -20
```

- [ ] **Step 3: Add `select_range/2` to `actions.ex`**

```elixir
  def select_range(
        %{"anchor_id" => anchor_id, "target_id" => target_id, "ordered_ids" => raw_ordered_ids},
        socket
      ) do
    # Filter client-provided IDs against visible agents to prevent scope leakage
    visible_ids = Selection.ids_from_agents(socket.assigns.agents)

    ordered_ids =
      raw_ordered_ids
      |> Enum.map(&Selection.normalize_id/1)
      |> Enum.filter(&MapSet.member?(visible_ids, &1))

    anchor = Selection.normalize_id(anchor_id)
    target = Selection.normalize_id(target_id)

    anchor_idx = Enum.find_index(ordered_ids, &(&1 == anchor))
    target_idx = Enum.find_index(ordered_ids, &(&1 == target))

    # If anchor or target are not in visible rows (invalid/stale), do nothing
    if is_nil(anchor_idx) or is_nil(target_idx) do
      {:noreply, socket}
    else
      range_ids =
        ordered_ids
        |> Enum.slice(min(anchor_idx, target_idx)..max(anchor_idx, target_idx))
        |> MapSet.new()

      selected = MapSet.union(socket.assigns.selected_ids, range_ids)

      socket =
        socket
        |> assign(:selected_ids, selected)
        |> assign(:select_mode, MapSet.size(selected) > 0)
        |> assign(:indeterminate_ids, Selection.compute_indeterminate_ids(selected, socket.assigns.agents))
        |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, socket.assigns.agents))

      {:noreply, socket}
    end
  end
```

- [ ] **Step 4: Wire event in `sessions.ex`**

```elixir
  def handle_event("select_range", params, socket),
    do: Actions.select_range(params, socket)
```

- [ ] **Step 5: Create `assets/js/hooks/shift_select.js`**

Single capture-phase listener. Tracks anchor on normal clicks; fires `select_range` on shift-clicks and calls `stopImmediatePropagation` to prevent `phx-click="toggle_select"` from also firing.

```js
/**
 * ShiftSelect
 *
 * Wraps the sessions list. Uses a single capture-phase listener to:
 * - Track the anchor row on normal checkbox clicks.
 * - Fire `select_range` on shift+click and cancel the phx-click handler.
 *
 * Capture phase is required because the checkbox has onclick="event.stopPropagation()"
 * to prevent row navigation. A bubble-phase listener on a wrapper would never see
 * the click. The capture handler runs before that stop fires.
 *
 * Usage:
 *   <div phx-hook="ShiftSelect" id="ps-list-shift-wrapper">
 *     <div id="ps-list" phx-update="stream" ...>
 *       <div data-row-id="123" ...>
 *         ...  (square_checkbox renders data-checkbox-area="true" on the label)
 *       </div>
 *     </div>
 *   </div>
 */
export const ShiftSelect = {
  mounted() {
    this._anchor = null

    this._onClick = (e) => {
      const checkboxArea = e.target.closest("[data-checkbox-area]")
      if (!checkboxArea || !this.el.contains(checkboxArea)) return

      const row = e.target.closest("[data-row-id]")
      if (!row || !this.el.contains(row)) return

      const id = row.dataset.rowId
      if (!id) return

      if (!e.shiftKey) {
        // Normal click — update anchor; let phx-click="toggle_select" handle the toggle
        this._anchor = id
        return
      }

      // Shift-click — fire range event
      if (!this._anchor || this._anchor === id) {
        this._anchor = id
        return
      }

      // Scope to #ps-list to avoid picking up stray data-row-id elements
      const list = this.el.querySelector("#ps-list")
      if (!list) return

      const orderedIds = Array.from(
        list.querySelectorAll("[data-row-id]")
      ).map((el) => el.dataset.rowId)

      this.pushEvent("select_range", {
        anchor_id: this._anchor,
        target_id: id,
        ordered_ids: orderedIds,
      })

      // Update anchor for chained shift-clicks
      this._anchor = id

      // stopPropagation prevents the event reaching LiveView's bubble-phase phx-click handler.
      // stopImmediatePropagation is redundant for this purpose but harmless.
      e.stopPropagation()
      e.stopImmediatePropagation()
      e.preventDefault()
    }

    this.el.addEventListener("click", this._onClick, true)
  },

  updated() {
    // After a LiveView patch (filter change, PubSub update), reset the anchor
    // if the anchored row is no longer in the DOM. The server guards against stale
    // anchors in select_range/2, but resetting here avoids silent no-ops on shift-click.
    if (this._anchor) {
      const list = this.el.querySelector("#ps-list")
      if (list && !list.querySelector(`[data-row-id="${this._anchor}"]`)) {
        this._anchor = null
      }
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick, true)
  },
}
```

- [ ] **Step 6: Register hook in `app.js`**

```js
import { ShiftSelect } from "./hooks/shift_select"
// ... existing hook registrations ...
Hooks.ShiftSelect = ShiftSelect
```

- [ ] **Step 7: Add `data-row-id` to stream items and `ShiftSelect` wrapper in `project_sessions_table.ex`**

Wrap the `#ps-list` div (`phx-hook` accepts one hook per element; wrapper gets `ShiftSelect`, inner div keeps `SessionsDropdownGuard`):

```heex
        <div phx-hook="ShiftSelect" id="ps-list-shift-wrapper">
          <div
            id="ps-list"
            phx-update="stream"
            phx-hook="SessionsDropdownGuard"
            class="divide-y divide-base-content/5"
          >
            <div
              :for={{dom_id, agent} <- @streams.session_list}
              id={dom_id}
              data-row-id={agent.id}
              class={
                if Map.get(@depths, agent.id, 0) > 0,
                  do: "ml-5 border-l-2 pl-3",
                  else: ""
              }
            >
              <.session_row ... />
            </div>
          </div>
        </div>
```

The `data-checkbox-area="true"` attr is now rendered by `square_checkbox` via the `checkbox_area={true}` prop added in Task 5 — no additional changes needed in `session_card.ex`.

- [ ] **Step 8: Run tests, verify PASS**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select 2>&1 | tail -10
```

- [ ] **Step 9: Run the full bulk-select test suite**

```bash
mix test test/eye_in_the_sky_web/live/project_live/sessions_test.exs --only bulk_select 2>&1 | tail -20
```

Expected: all 12 tagged tests pass. To run a single test in isolation, use its specific tag (e.g. `--only bulk_select_range`).

- [ ] **Step 10: Compile check**

```bash
MIX_ENV=test mix compile --warnings-as-errors 2>&1 | tail -10
```

- [ ] **Step 11: Commit**

```bash
git add assets/js/hooks/shift_select.js \
        assets/js/app.js \
        lib/eye_in_the_sky_web/components/project_sessions_table.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex \
        lib/eye_in_the_sky_web/live/project_live/sessions.ex \
        test/eye_in_the_sky_web/live/project_live/sessions_test.exs
git commit -m "feat: shift-click range selection in session list"
```

---

## Deferred (v2)

- Keyboard shortcuts (↑↓ Space)
- Select subtree as a separate bulk action
- Sticky toolbar that replaces the top nav bar (requires NavHook top-bar swap)
- Select all filtered results when pagination/virtualization is added

---

## Spec Coverage

| Requirement | Task |
|-------------|------|
| Selection helper module | Task 1 |
| Selected row bg highlight | Task 2 |
| Filter-resilient selection | Task 3 |
| Select-all visible semantics (preserves off-screen) | Task 3 |
| Off-screen count in toolbar | Task 3 |
| Bulk archive with confirm + project scoping | Task 4 |
| Parent indeterminate checkbox | Task 5 |
| Select-all indeterminate | Task 5 |
| `checkbox_area` on label (needed by shift hook) | Task 5 |
| Shift-click range selection | Task 6 |

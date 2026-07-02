# Bulk Select / Delete Pattern for LiveView Pages

Implemented on the Teams page (commit `9312b499`). Use this as the reference when adding the same behavior to any other list page (channels, notes, agents, etc.).

---

## What it does

- Per-row checkbox that appears on hover, stays visible once anything is selected
- Selection toolbar with select-all (indeterminate state), count, archive/delete button, and X to exit
- Shift+click range selection
- Soft delete (archive) on bulk action
- Full visual feedback: selected row highlight + checked checkbox via stream reinsertion

---

## Files touched

| File | What changed |
|------|--------------|
| `lib/eye_in_the_sky/<context>.ex` | Added `batch_delete_<entities>/1` |
| `lib/eye_in_the_sky_web/live/project_live/<page>.ex` | Selection assigns, 5 event handlers, `reinsert_all_<entities>/1`, template changes |

No new files. No new JS. The `ShiftSelect` hook at `assets/js/hooks/shift_select.js` is shared — just wire it in the template.

---

## Step 1 — Context: add `batch_delete/1`

Soft delete only. Never hard-delete. Call the existing single-delete function in a loop:

```elixir
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

The single-delete function already broadcasts PubSub (`:team_deleted`), so the stream removes each row automatically via the existing `handle_info` clause. No extra broadcast needed.

---

## Step 2 — LiveView: assigns in mount

```elixir
|> assign(:selected_ids, MapSet.new())
|> assign(:select_mode, false)
```

`selected_ids` is always a `MapSet` of **string** IDs (`to_string(entity.id)`). IDs from HTML attributes are strings; IDs in Elixir structs are integers — normalize to strings at every boundary.

Also ensure mount assigns the full entity list to a stable assign (e.g. `all_teams`) that is NOT the stream itself. Event handlers read from this assign to find structs for `stream_insert`.

---

## Step 3 — LiveView: event handlers

### `toggle_select`

The core toggle. Called on individual checkbox click.

```elixir
def handle_event("toggle_select", %{"id" => id}, socket) do
  id = to_string(id)
  was_select_mode = socket.assigns.select_mode
  selected_ids = socket.assigns.selected_ids

  selected_ids =
    if MapSet.member?(selected_ids, id),
      do: MapSet.delete(selected_ids, id),
      else: MapSet.put(selected_ids, id)

  select_mode = MapSet.size(selected_ids) > 0

  socket =
    socket
    |> assign(:selected_ids, selected_ids)
    |> assign(:select_mode, select_mode)

  # CRITICAL: streams don't re-render rows when assigns change.
  # When mode flips: reinsert ALL rows so checkboxes appear/disappear everywhere.
  # When mode stays: reinsert just the toggled row so its checked state updates.
  socket =
    if select_mode != was_select_mode do
      reinsert_all_entities(socket)
    else
      case Enum.find(socket.assigns.all_teams, &(to_string(&1.id) == id)) do
        nil -> socket
        entity -> stream_insert(socket, :team_list, entity)
      end
    end

  {:noreply, socket}
end
```

### `toggle_select_all`

```elixir
def handle_event("toggle_select_all", _params, socket) do
  all_ids =
    socket.assigns.all_teams
    |> Enum.map(&to_string(&1.id))
    |> MapSet.new()

  {selected_ids, select_mode} =
    if MapSet.size(socket.assigns.selected_ids) == MapSet.size(all_ids) do
      {MapSet.new(), false}
    else
      {all_ids, true}
    end

  socket =
    socket
    |> assign(:selected_ids, selected_ids)
    |> assign(:select_mode, select_mode)
    |> reinsert_all_entities()

  {:noreply, socket}
end
```

### `delete_selected`

```elixir
def handle_event("delete_selected", _params, socket) do
  ids =
    socket.assigns.selected_ids
    |> MapSet.to_list()
    |> Enum.map(&String.to_integer/1)

  Teams.batch_delete_teams(ids)

  # Don't manually remove from stream here — the PubSub broadcast from batch_delete
  # triggers handle_info(:team_deleted) which removes each row.
  {:noreply,
   socket
   |> assign(:selected_ids, MapSet.new())
   |> assign(:select_mode, false)}
end
```

### `exit_select_mode`

```elixir
def handle_event("exit_select_mode", _params, socket) do
  socket =
    socket
    |> assign(:selected_ids, MapSet.new())
    |> assign(:select_mode, false)
    |> reinsert_all_entities()

  {:noreply, socket}
end
```

### `select_range` (shift+click)

```elixir
def handle_event(
      "select_range",
      %{"anchor_id" => anchor_id, "target_id" => target_id, "ordered_ids" => raw_ordered_ids},
      socket
    ) do
  # Filter to IDs actually in the visible list (guards against stale DOM state)
  visible_ids =
    socket.assigns.all_teams
    |> Enum.map(&to_string(&1.id))
    |> MapSet.new()

  ordered_ids =
    raw_ordered_ids
    |> Enum.map(&to_string/1)
    |> Enum.filter(&MapSet.member?(visible_ids, &1))

  anchor = to_string(anchor_id)
  target = to_string(target_id)

  anchor_idx = Enum.find_index(ordered_ids, &(&1 == anchor))
  target_idx = Enum.find_index(ordered_ids, &(&1 == target))

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
      |> reinsert_all_entities()    # MUST reinsert — multiple rows changed state

    {:noreply, socket}
  end
end
```

### `reinsert_all_entities/1` private helper

```elixir
defp reinsert_all_teams(socket) do
  Enum.reduce(socket.assigns.all_teams, socket, fn team, acc ->
    stream_insert(acc, :team_list, team)
  end)
end
```

The stream name (`:team_list`) must match what `stream/3` was called with in mount.

---

## Step 4 — Template: selection toolbar

Render above the stream div, inside the non-empty branch. Show only when `MapSet.size(@selected_ids) > 0`:

```heex
<%= if MapSet.size(@selected_ids) > 0 do %>
  <% all_selected = MapSet.size(@selected_ids) == length(@all_teams) && length(@all_teams) > 0 %>
  <% some_selected = MapSet.size(@selected_ids) > 0 && !all_selected %>
  <div class="mt-2 flex items-center gap-3 pl-4 sm:pl-0 py-1.5">
    <div phx-click="toggle_select_all" class="cursor-pointer sm:-ml-5">
      <.square_checkbox
        id="<entity>-select-all"
        checked={all_selected}
        indeterminate={some_selected}
        aria-label="Select all"
      />
    </div>
    <span class="text-mini text-base-content/50 font-medium">
      {MapSet.size(@selected_ids)} selected
    </span>
    <button
      phx-click="delete_selected"
      class="btn btn-ghost btn-xs text-warning/70 hover:text-warning hover:bg-warning/10 gap-1 min-h-[44px] min-w-[44px]"
    >
      <.icon name="hero-archive-box-mini" class="size-3.5" /> Archive
    </button>
    <button
      phx-click="exit_select_mode"
      class="ml-auto btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px] text-base-content/40 hover:text-base-content/70"
      aria-label="Exit select mode"
    >
      <.icon name="hero-x-mark" class="size-4" />
    </button>
  </div>
<% end %>
```

Note: `indeterminate` is a prop on `square_checkbox` that renders the dash state. It requires `checked={false}` when `indeterminate={true}` — the component handles mutual exclusion.

---

## Step 5 — Template: ShiftSelect wrapper + per-row checkbox

Wrap the stream div with the `ShiftSelect` hook. Give `data-list-id` the value of the stream element's `id`:

```heex
<div phx-hook="ShiftSelect" id="<entity>-list-shift-wrapper" data-list-id="<entity>-list">
  <div id="<entity>-list" phx-update="stream" class="divide-y divide-base-content/8">
    <div
      :for={{dom_id, entity} <- @streams.<entity>_list}
      id={dom_id}
      data-row-id={entity.id}           <!-- REQUIRED: ShiftSelect reads this -->
      class={[
        "py-1 group/row flex items-center gap-1 relative",
        if(MapSet.member?(@selected_ids, to_string(entity.id)),
          do: "bg-primary/5 ring-1 ring-primary/20 ring-inset rounded-lg",
          else: ""
        )
      ]}
    >
      <!-- Checkbox: absolutely positioned, appears on hover or when in select mode -->
      <div
        class={[
          "p-1 absolute z-10 top-1/2 -translate-y-1/2",
          "left-4 sm:left-[-0.875rem]",
          if(@select_mode,
            do: "opacity-100 scale-100",
            else: "opacity-0 scale-75 group-hover/row:opacity-100 group-hover/row:scale-100 transition duration-100"
          )
        ]}
        phx-click="toggle_select"
        phx-value-id={entity.id}
      >
        <.square_checkbox
          id={"<entity>-checkbox-#{entity.id}"}
          checked={MapSet.member?(@selected_ids, to_string(entity.id))}
          checkbox_area={true}           <!-- REQUIRED: ShiftSelect detects [data-checkbox-area] -->
          aria-label={"Select #{entity.name}"}
        />
      </div>

      <!-- Row content: shift right in select_mode to make room for checkbox on mobile -->
      <div class={["flex items-center gap-1 w-full min-w-0", if(@select_mode, do: "pl-10 sm:pl-0", else: "")]}>
        <!-- ... existing row content ... -->
      </div>
    </div>
  </div>
</div>
```

Key attributes:
- `data-row-id={entity.id}` on the row div — ShiftSelect reads this to identify the row
- `checkbox_area={true}` on `square_checkbox` — renders `data-checkbox-area="true"` on the label, which is how ShiftSelect detects checkbox clicks vs row content clicks
- Named group `group/row` so hover variants don't bleed to parent elements

---

## Critical gotcha: streams don't re-render on assign change

This is the most important thing to understand. With `phx-update="stream"`, LiveView does **not** re-render stream rows when socket assigns change. A row is only updated in the DOM when you call `stream_insert` for it explicitly.

This means:

| Action | What breaks if you skip reinsert | Fix |
|--------|----------------------------------|-----|
| mode flips (first select, or last deselect) | Checkboxes don't appear/disappear on other rows | `reinsert_all_entities` |
| toggle non-first row (mode already true) | Second clicked checkbox stays unchecked visually | Targeted `stream_insert` for that one row |
| toggle_select_all | All rows stay at old checked state | `reinsert_all_entities` |
| select_range (shift+click) | Range rows stay unchecked, no highlight | `reinsert_all_entities` |
| exit_select_mode | Rows keep showing as selected/highlighted | `reinsert_all_entities` |

Rule: any handler that changes `selected_ids` or `select_mode` **must** reinsert all affected rows. When one row changes: targeted `stream_insert`. When many rows or unknown count: `reinsert_all_entities`.

---

## How `ShiftSelect` works

Source: `assets/js/hooks/shift_select.js`

It attaches a **capture-phase** click listener to the wrapper div (not bubble phase). This is required because the checkbox label has `onclick` that stops propagation — capture fires before that.

On every checkbox click:
1. Finds `[data-checkbox-area]` to confirm it's a checkbox click (not a row link click)
2. Finds `[data-row-id]` to get the row ID
3. If no shift key: stores `this._anchor = id`, returns. Let the `phx-click="toggle_select"` bubble normally.
4. If shift key + anchor exists and differs from target:
   - Collects all `[data-row-id]` elements inside the list element (identified by `data-list-id` on the wrapper)
   - Fires `pushEvent("select_range", {anchor_id, target_id, ordered_ids})`
   - Stops propagation + prevents default so `phx-click="toggle_select"` does NOT fire

The hook fires `select_range` with the full ordered ID list from the current DOM. The server handler filters this against `all_teams` to exclude stale IDs.

On `updated()`, the hook clears `this._anchor` if the anchored row was removed from the DOM (e.g. filtered out, deleted).

---

## Wiring checklist

- [ ] `batch_delete_<entities>/1` added to context module
- [ ] `:selected_ids` and `:select_mode` assigned in mount
- [ ] `all_<entities>` assign populated in mount (the full struct list, not just the stream)
- [ ] `toggle_select` handler with targeted reinsert for steady state
- [ ] `toggle_select_all` handler calling `reinsert_all_entities`
- [ ] `delete_selected` handler clearing selection (PubSub handles stream removal)
- [ ] `exit_select_mode` handler calling `reinsert_all_entities`
- [ ] `select_range` handler calling `reinsert_all_entities`
- [ ] `reinsert_all_entities/1` private helper using `stream_insert` in reduce
- [ ] Toolbar HEEx showing when `MapSet.size(@selected_ids) > 0`
- [ ] Stream div wrapped in `<div phx-hook="ShiftSelect" data-list-id="...">` wrapper
- [ ] `data-row-id={entity.id}` on every row div
- [ ] `checkbox_area={true}` on `square_checkbox` in each row
- [ ] `group/row` named group on row div (not bare `group`) to scope hover variants

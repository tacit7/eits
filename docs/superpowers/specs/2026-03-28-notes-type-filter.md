# Notes Type Filter — Spec

**Date:** 2026-03-28

## Overview

Add a single-select dropdown to the notes filter bar that lets users filter notes by `parent_type`. Applies to both the overview notes page (`/notes`) and the project notes page (`/projects/:id/notes`).

## Note Types

The `notes.parent_type` column is validated to one of: `session`, `task`, `agent`, `project`, `system`.

## UI Change

### Filter bar (NotesList component)

Current bar: `[search input] [starred toggle] [sort select]`

New bar: `[search input] [starred toggle] [type select] [sort select]`

The type select renders as:

```
All Types | Session | Agent | Project | Task | System
```

Same DaisyUI `select select-xs` styling as the existing sort select.

### New attr on `NotesList`

```elixir
attr :type_filter, :string, default: "all"
```

Fires a `filter_type` event with `value` on change (`phx-change`).

## State

Both `OverviewLive.Notes` and `ProjectLive.Notes`:

- Add `:type_filter` assigned to `"all"` in `mount/3`.

## Event Handling

Add `handle_filter_type/3` to `NotesHelpers`:

```elixir
def handle_filter_type(%{"value" => type}, socket, reload_fn) do
  {:noreply, socket |> assign(:type_filter, type) |> reload_fn.()}
end
```

Both LiveViews add:

```elixir
def handle_event("filter_type", params, socket),
  do: handle_filter_type(params, socket, &load_notes/1)
```

## Query Change

In each `load_notes/1`, after the base query is built, add:

```elixir
base =
  if type_filter != "all" do
    from(n in base, where: n.parent_type == ^type_filter)
  else
    base
  end
```

In `ProjectLive.Notes`, the base query already uses `parent_type in ["session", "sessions"]` etc. The type filter is applied on top of that via an additional `where` clause.

The `search_notes` path (when `query != ""`) does not currently support type filtering; it will be left unchanged — search results show all types regardless of the type select. This is an acceptable limitation for the initial implementation.

## Files Changed

| File | Change |
|------|--------|
| `lib/eye_in_the_sky_web/components/notes_list.ex` | Add `type_filter` attr; add type `<select>` to filter bar |
| `lib/eye_in_the_sky_web/live/shared/notes_helpers.ex` | Add `handle_filter_type/3` |
| `lib/eye_in_the_sky_web/live/overview_live/notes.ex` | Mount assign, event handler, `load_notes` filter |
| `lib/eye_in_the_sky_web/live/project_live/notes.ex` | Mount assign, event handler, `load_notes` filter |

## Out of Scope

- Filtering within full-text search results
- Multi-select type filtering
- URL param persistence of the type filter

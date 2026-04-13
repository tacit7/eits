# Project Bookmarks Design

**Date:** 2026-04-03
**Status:** Approved (v2 — post-review)

## Overview

Add a bookmark toggle to each project in the sidebar. Bookmarked projects sort to the top of the project list. Bookmark state persists in the database.

---

## Decisions

### Issue 1 — Ownership: global vs per-user

This is a single-user monitoring app. There is no user table and no authentication scoping per user. Bookmarks are **project-level metadata** — functionally equivalent to a "pinned" flag. A `bookmarked boolean` field on `projects` is correct and sufficient. No join table needed.

### Issue 5 — Authorization

The sidebar only renders project IDs loaded from `list_projects_for_sidebar/0`, which is server-controlled. A user cannot bookmark an arbitrary project ID they don't already see. No additional authorization guard is needed for the toggle handler; document this assumption explicitly.

### Issue 4 — Full list reload

Reload the full list after every toggle. Projects lists are small in practice. Optimize only if benchmarks warrant it.

---

## Schema Change

Add a single boolean column to the `projects` table:

```elixir
add :bookmarked, :boolean, default: false, null: false
```

Migration: `mix ecto.gen.migration add_bookmarked_to_projects`

Update `Project.changeset/2` to cast `:bookmarked`.

---

## Context Changes (`projects.ex`)

### Issue 6 — Sidebar-specific query

Do **not** change `list_projects/0`. Add a new function used only by the sidebar:

```elixir
def list_projects_for_sidebar do
  Project
  |> where([p], p.active == true)
  |> order_by([p], [
    asc: not p.bookmarked,
    asc: fragment("lower(?)", p.name),
    asc: p.id
  ])
  |> Repo.all()
end
```

This keeps bookmark ordering isolated from admin pages, pickers, and API responses.

### Issue 7 — Sort stability

Sort key: `[asc: not p.bookmarked, asc: lower(name), asc: id]`

- Case-insensitive name sort via `fragment("lower(?)", p.name)`
- Stable tertiary sort by `id` prevents non-deterministic ordering for duplicates
- Inactive/archived projects (`active: false`) excluded from sidebar entirely

### Issue 2 & 3 — Context API (explicit setter, not stale-state toggle)

Replace the flip-on-struct approach with an explicit setter that operates by ID:

```elixir
def set_bookmarked(project_id, bookmarked) when is_boolean(bookmarked) do
  case get_project(project_id) do
    nil -> {:error, :not_found}
    project ->
      project
      |> Project.changeset(%{bookmarked: bookmarked})
      |> Repo.update()
  end
end
```

No stale-in-memory state. The UI passes the desired new state explicitly.

### Issue 10 — PubSub broadcast

After a successful `set_bookmarked`, broadcast a `project_updated` event via the `Events` module so all sidebar instances (multiple tabs) stay in sync.

Add to `events.ex`:

```elixir
def subscribe_projects, do: sub("projects")

def project_updated(project),
  do: broadcast("projects", {:project_updated, project})
```

Add `"projects"` to the topics table in `events.ex`.

---

## Sidebar LiveComponent (`sidebar.ex`)

Subscribe to projects topic in `mount/1`:

```elixir
Events.subscribe_projects()
```

Handle incoming PubSub events:

```elixir
def handle_info({:project_updated, _project}, socket) do
  {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
end
```

Update initial load to use `list_projects_for_sidebar/0`.

### Issue 3 — Thin event handler

Move orchestration into the context. Handler only passes explicit desired state:

```elixir
def handle_event("set_bookmark", %{"id" => id, "value" => value}, socket) do
  bookmarked = value == "true"
  # Authorization: id is safe — only project IDs from the loaded list are rendered
  {:ok, project} = Projects.set_bookmarked(id, bookmarked)
  Events.project_updated(project)
  {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
end
```

---

## UI (`projects_section.ex`)

Add a bookmark button to the hover actions row (same row as rename, delete, new session).

- Bookmarked: filled `hero-bookmark-solid` icon
- Not bookmarked: outline `hero-bookmark` icon

Button sends `phx-click="set_bookmark"` with:
- `phx-value-id={project.id}`
- `phx-value-value={!project.bookmarked}` — explicit desired next state from the template

### Issue 9 — Duplicate-click prevention

Use `phx-disable-with` on the button to disable it while the event is in flight:

```heex
<button
  phx-click="set_bookmark"
  phx-value-id={project.id}
  phx-value-value={"#{!project.bookmarked}"}
  phx-target={@myself}
  phx-disable-with=""
>
  <.icon name={if project.bookmarked, do: "hero-bookmark-solid", else: "hero-bookmark"} class="w-4 h-4" />
</button>
```

---

## No JS Changes

Client-side filter in `sidebar_state.js` uses `data-project-name`. Sort order is server-rendered. No hook changes needed.

---

## Testing

### Unit tests (`projects_test.exs`)

- `set_bookmarked/2` sets field to `true`
- `set_bookmarked/2` sets field to `false`
- `list_projects_for_sidebar/0` returns bookmarked projects before non-bookmarked
- Toggling a non-bookmarked project moves it above non-bookmarked projects (order test)
- Toggling a bookmarked project off moves it back into alphabetical position
- Multiple bookmarked projects remain internally sorted by name (case-insensitive)
- Inactive projects are excluded from sidebar list

### Component tests (`projects_section_test.exs`)

- Bookmark button is present in the hover actions row
- Filled icon rendered when `project.bookmarked` is `true`
- Outline icon rendered when `project.bookmarked` is `false`
- `phx-disable-with` attribute present on bookmark button

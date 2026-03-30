# Notes Type Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single-select "Type" dropdown to the notes filter bar that filters notes by `parent_type` on both `/notes` and `/projects/:id/notes`.

**Architecture:** The `NotesList` component gains a `type_filter` attr and a new `<select>` element. Both `OverviewLive.Notes` and `ProjectLive.Notes` gain a `:type_filter` socket assign, a `filter_type` event handler (delegated through the shared `NotesHelpers`), and an additional `where` clause in their `load_notes/1` functions.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, DaisyUI (Tailwind CSS), HEEx templates.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/eye_in_the_sky_web/components/notes_list.ex` | Modify | Add `type_filter` attr + `<select>` UI |
| `lib/eye_in_the_sky_web/live/shared/notes_helpers.ex` | Modify | Add `handle_filter_type/3` |
| `lib/eye_in_the_sky_web/live/overview_live/notes.ex` | Modify | Mount assign, event handler, query filter |
| `lib/eye_in_the_sky_web/live/project_live/notes.ex` | Modify | Mount assign, event handler, query filter |

---

### Task 1: Add `handle_filter_type/3` to `NotesHelpers`

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/shared/notes_helpers.ex`

- [ ] **Step 1: Add `handle_filter_type/3` after `handle_sort_notes/3`**

In `lib/eye_in_the_sky_web/live/shared/notes_helpers.ex`, add this function immediately after `handle_sort_notes/3` (currently ends around line 21):

```elixir
def handle_filter_type(%{"value" => type}, socket, reload_fn) do
  {:noreply, socket |> assign(:type_filter, type) |> reload_fn.()}
end
```

- [ ] **Step 2: Verify the file compiles**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix compile 2>&1 | grep -E "error|warning"
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/live/shared/notes_helpers.ex
git commit -m "feat: add handle_filter_type/3 to NotesHelpers"
```

---

### Task 2: Update `NotesList` component — add `type_filter` attr and dropdown

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/notes_list.ex`

- [ ] **Step 1: Add the `type_filter` attr declaration**

In `lib/eye_in_the_sky_web/components/notes_list.ex`, replace the existing attr block:

```elixir
attr :notes, :list, required: true
attr :starred_filter, :boolean, default: false
attr :search_query, :string, default: ""
attr :sort_by, :string, default: "newest"
attr :empty_id, :string, default: "notes-empty"
attr :editing_note_id, :integer, default: nil
attr :current_path, :string, default: "/notes"
```

With:

```elixir
attr :notes, :list, required: true
attr :starred_filter, :boolean, default: false
attr :search_query, :string, default: ""
attr :sort_by, :string, default: "newest"
attr :type_filter, :string, default: "all"
attr :empty_id, :string, default: "notes-empty"
attr :editing_note_id, :integer, default: nil
attr :current_path, :string, default: "/notes"
```

- [ ] **Step 2: Add the type `<select>` to the filter bar**

In the `~H"""` template, locate the filter bar. Insert a new `<form phx-change="filter_type">` block between the starred button and the existing sort form:

```heex
<button
  type="button"
  phx-click="toggle_starred_filter"
  class={"flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all duration-150 " <>
    if(@starred_filter,
      do: "bg-warning/10 text-warning",
      else: "text-base-content/35 hover:text-base-content/50 hover:bg-base-200/40"
    )}
>
  <.icon
    name={if @starred_filter, do: "hero-star-solid", else: "hero-star"}
    class="w-3.5 h-3.5"
  /> Starred
</button>
<form phx-change="filter_type">
  <label for={"#{@empty_id}-type"} class="sr-only">Filter by type</label>
  <select
    name="value"
    id={"#{@empty_id}-type"}
    class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-0 h-8 text-xs"
  >
    <option value="all" selected={@type_filter == "all"}>All Types</option>
    <option value="session" selected={@type_filter == "session"}>Session</option>
    <option value="agent" selected={@type_filter == "agent"}>Agent</option>
    <option value="project" selected={@type_filter == "project"}>Project</option>
    <option value="task" selected={@type_filter == "task"}>Task</option>
    <option value="system" selected={@type_filter == "system"}>System</option>
  </select>
</form>
<form phx-change="sort_notes">
```

- [ ] **Step 3: Verify compilation**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix compile 2>&1 | grep -E "error|warning"
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/components/notes_list.ex
git commit -m "feat: add type filter dropdown to NotesList component"
```

---

### Task 3: Wire up `OverviewLive.Notes`

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/overview_live/notes.ex`

- [ ] **Step 1: Add `:type_filter` assign in `mount/3`**

In `mount/3`, add `:type_filter` before the `load_notes()` call:

```elixir
|> assign(:show_quick_note_modal, false)
|> assign(:type_filter, "all")
|> load_notes()
```

- [ ] **Step 2: Add `filter_type` event handler**

After the `handle_event("sort_notes", ...)` clause, add:

```elixir
@impl true
def handle_event("filter_type", params, socket),
  do: handle_filter_type(params, socket, &load_notes/1)
```

- [ ] **Step 3: Apply the filter in `load_notes/1`**

Replace the current `defp load_notes(socket)` body with:

```elixir
defp load_notes(socket) do
  query = socket.assigns.search_query
  starred_only = socket.assigns.starred_filter
  sort_by = socket.assigns.notes_sort_by
  type_filter = socket.assigns.type_filter
  order = if sort_by == "oldest", do: [asc: :created_at], else: [desc: :created_at]

  notes =
    if query != "" and String.trim(query) != "" do
      Notes.search_notes(query, [], starred: starred_only)
    else
      base =
        from(n in Note,
          order_by: ^order,
          limit: 200
        )

      base = if starred_only, do: from(n in base, where: n.starred == 1), else: base

      base =
        if type_filter != "all" do
          from(n in base, where: n.parent_type == ^type_filter)
        else
          base
        end

      Repo.all(base)
    end

  assign(socket, :notes, notes)
end
```

- [ ] **Step 4: Pass `type_filter` to `NotesList` in `render/1`**

Locate `<.notes_list ...>` and add `type_filter={@type_filter}`:

```heex
<.notes_list
  notes={@notes}
  starred_filter={@starred_filter}
  search_query={@search_query}
  sort_by={@notes_sort_by}
  type_filter={@type_filter}
  empty_id="overview-notes-empty"
  editing_note_id={@editing_note_id}
  current_path="/notes"
/>
```

- [ ] **Step 5: Verify compilation**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix compile 2>&1 | grep -E "error|warning"
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web/live/overview_live/notes.ex
git commit -m "feat: wire type filter into OverviewLive.Notes"
```

---

### Task 4: Wire up `ProjectLive.Notes`

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/project_live/notes.ex`

- [ ] **Step 1: Add `:type_filter` assign in `mount/3`**

In the success branch of `mount/3`, add `:type_filter` before `load_notes()`:

```elixir
|> assign(:show_quick_note_modal, false)
|> assign(:type_filter, "all")
|> load_notes()
```

- [ ] **Step 2: Add `filter_type` event handler**

After the `handle_event("sort_notes", ...)` clause, add:

```elixir
@impl true
def handle_event("filter_type", params, socket),
  do: handle_filter_type(params, socket, &load_notes/1)
```

- [ ] **Step 3: Apply the filter in `load_notes/1`**

Replace the current `defp load_notes(socket)` body with:

```elixir
defp load_notes(socket) do
  project = socket.assigns.project
  agent_ids = Enum.map(project.agents, & &1.id)

  session_ids =
    from(s in EyeInTheSky.Sessions.Session,
      where: s.agent_id in ^agent_ids,
      select: s.id
    )
    |> Repo.all()

  query = socket.assigns.search_query
  starred_only = socket.assigns.starred_filter
  sort_by = socket.assigns.notes_sort_by
  type_filter = socket.assigns.type_filter
  order = if sort_by == "oldest", do: [asc: :created_at], else: [desc: :created_at]

  notes =
    if query != "" and String.trim(query) != "" do
      Notes.search_notes(query, agent_ids,
        project_id: project.id,
        session_ids: session_ids,
        starred: starred_only
      )
    else
      project_id_str = to_string(project.id)
      agent_id_strs = Enum.map(agent_ids, &to_string/1)
      session_id_strs = Enum.map(session_ids, &to_string/1)

      base =
        from(n in EyeInTheSky.Notes.Note,
          where:
            (n.parent_type in ["project", "projects"] and n.parent_id == ^project_id_str) or
              (n.parent_type in ["agent", "agents"] and n.parent_id in ^agent_id_strs) or
              (n.parent_type in ["session", "sessions"] and
                 n.parent_id in ^session_id_strs),
          order_by: ^order
        )

      base = if starred_only, do: from(n in base, where: n.starred == 1), else: base

      base =
        if type_filter != "all" do
          from(n in base, where: n.parent_type == ^type_filter)
        else
          base
        end

      Repo.all(base)
    end

  assign(socket, :notes, notes)
end
```

- [ ] **Step 4: Pass `type_filter` to `NotesList` in `render/1`**

Locate `<.notes_list ...>` and add `type_filter={@type_filter}`:

```heex
<.notes_list
  notes={@notes}
  starred_filter={@starred_filter}
  search_query={@search_query}
  sort_by={@notes_sort_by}
  type_filter={@type_filter}
  empty_id="project-notes-empty"
  editing_note_id={@editing_note_id}
  current_path={~p"/projects/#{@project.id}/notes"}
/>
```

- [ ] **Step 5: Verify compilation**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix compile 2>&1 | grep -E "error|warning"
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web/live/project_live/notes.ex
git commit -m "feat: wire type filter into ProjectLive.Notes"
```

---

### Task 5: Final compile check

- [ ] **Step 1: Clean compile with warnings-as-errors**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix compile --warnings-as-errors 2>&1
```

Expected: exits 0, no errors or warnings.

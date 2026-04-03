# Project Bookmarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bookmark toggle to the project sidebar so bookmarked projects bubble to the top of the list, persisted in the database.

**Architecture:** Add a `bookmarked` boolean to the `projects` table. Introduce `list_projects_for_sidebar/0` (bookmark-first, case-insensitive name sort) and `set_bookmarked/2` (explicit setter, no stale-state flip) in the Projects context. The Sidebar LiveComponent handles the event, broadcasts via a new `"projects"` PubSub topic so all open tabs stay in sync. The UI adds a bookmark button to each project's dropdown menu.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto, PostgreSQL, HEEx, Heroicons, Phoenix.PubSub via `EyeInTheSky.Events`

---

## File Map

| Action | File |
|--------|------|
| Create | `priv/repo/migrations/<timestamp>_add_bookmarked_to_projects.exs` |
| Modify | `lib/eye_in_the_sky/projects/project.ex` |
| Modify | `lib/eye_in_the_sky/projects.ex` |
| Modify | `lib/eye_in_the_sky/events.ex` |
| Modify | `lib/eye_in_the_sky_web/components/sidebar.ex` |
| Modify | `lib/eye_in_the_sky_web/components/sidebar/projects_section.ex` |
| Modify | `test/eye_in_the_sky_web/components/projects_section_test.exs` |
| Create | `test/eye_in_the_sky/projects_bookmarks_test.exs` |

---

### Task 1: Migration — add `bookmarked` to `projects`

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_bookmarked_to_projects.exs`

- [ ] **Step 1: Generate the migration**

```bash
mix ecto.gen.migration add_bookmarked_to_projects
```

Expected: a new file created under `priv/repo/migrations/` named `<timestamp>_add_bookmarked_to_projects.exs`.

- [ ] **Step 2: Fill in the migration**

Open the generated file and replace its contents with:

```elixir
defmodule EyeInTheSky.Repo.Migrations.AddBookmarkedToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :bookmarked, :boolean, default: false, null: false
    end
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected output ends with: `[info] == Migrated <timestamp> in <N>s`

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: add bookmarked column to projects"
```

---

### Task 2: Update `Project` schema and changeset

**Files:**
- Modify: `lib/eye_in_the_sky/projects/project.ex`

- [ ] **Step 1: Write the failing test**

Create `test/eye_in_the_sky/projects_bookmarks_test.exs`:

```elixir
defmodule EyeInTheSky.ProjectsBookmarksTest do
  use EyeInTheSky.DataCase

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Projects.Project

  defp create_project(name) do
    {:ok, project} =
      Projects.create_project(%{name: name, path: "/tmp/#{name}-#{System.unique_integer([:positive])}"})
    project
  end

  describe "Project.changeset/2 with bookmarked" do
    test "casts bookmarked field" do
      project = create_project("test")
      changeset = Project.changeset(project, %{bookmarked: true})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :bookmarked) == true
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
mix test test/eye_in_the_sky/projects_bookmarks_test.exs
```

Expected: test fails — `bookmarked` field not in schema yet.

- [ ] **Step 3: Add `bookmarked` to the schema and changeset**

In `lib/eye_in_the_sky/projects/project.ex`, add after line 14 (`field :active, :boolean, default: true`):

```elixir
    field :bookmarked, :boolean, default: false
```

Update the `cast` call in `changeset/2` (line 28) to include `:bookmarked`:

```elixir
    |> cast(attrs, [:name, :slug, :path, :remote_url, :git_remote, :repo_url, :branch, :active, :bookmarked])
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
mix test test/eye_in_the_sky/projects_bookmarks_test.exs
```

Expected: 1 test, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky/projects/project.ex test/eye_in_the_sky/projects_bookmarks_test.exs
git commit -m "feat: add bookmarked field to Project schema"
```

---

### Task 3: Add `set_bookmarked/2` and `list_projects_for_sidebar/0` to context

**Files:**
- Modify: `lib/eye_in_the_sky/projects.ex`
- Modify: `test/eye_in_the_sky/projects_bookmarks_test.exs`

- [ ] **Step 1: Write failing tests**

Append these describes to `test/eye_in_the_sky/projects_bookmarks_test.exs`:

```elixir
  describe "set_bookmarked/2" do
    test "sets bookmarked to true" do
      project = create_project("alpha")
      assert {:ok, updated} = Projects.set_bookmarked(project.id, true)
      assert updated.bookmarked == true
    end

    test "sets bookmarked to false" do
      {:ok, project} =
        Projects.create_project(%{
          name: "beta",
          path: "/tmp/beta-#{System.unique_integer([:positive])}",
          bookmarked: true
        })
      assert {:ok, updated} = Projects.set_bookmarked(project.id, false)
      assert updated.bookmarked == false
    end

    test "returns error for unknown id" do
      assert {:error, :not_found} = Projects.set_bookmarked(999_999, true)
    end
  end

  describe "list_projects_for_sidebar/0" do
    test "returns bookmarked projects before non-bookmarked" do
      a = create_project("aardvark")
      b = create_project("zebra")
      {:ok, b} = Projects.set_bookmarked(b.id, true)

      ids = Projects.list_projects_for_sidebar() |> Enum.map(& &1.id)
      zebra_pos = Enum.find_index(ids, &(&1 == b.id))
      aardvark_pos = Enum.find_index(ids, &(&1 == a.id))

      assert zebra_pos < aardvark_pos
    end

    test "multiple bookmarked projects are name-sorted among themselves (case-insensitive)" do
      {:ok, c} = Projects.create_project(%{name: "Cucumber", path: "/tmp/c-#{System.unique_integer([:positive])}", bookmarked: true})
      {:ok, a} = Projects.create_project(%{name: "apple", path: "/tmp/a-#{System.unique_integer([:positive])}", bookmarked: true})
      {:ok, b} = Projects.create_project(%{name: "Banana", path: "/tmp/b-#{System.unique_integer([:positive])}", bookmarked: true})

      bookmarked_ids =
        Projects.list_projects_for_sidebar()
        |> Enum.filter(& &1.bookmarked)
        |> Enum.map(& &1.id)

      assert bookmarked_ids == [a.id, b.id, c.id]
    end

    test "unbookmarking a project moves it back below bookmarked ones" do
      move = create_project("move")
      {:ok, _} = Projects.set_bookmarked(move.id, true)
      {:ok, _} = Projects.set_bookmarked(move.id, false)

      result = Projects.list_projects_for_sidebar()
      assert Enum.find(result, &(&1.id == move.id)).bookmarked == false
    end

    test "inactive projects are excluded" do
      Projects.create_project(%{name: "hidden", path: "/tmp/h-#{System.unique_integer([:positive])}", active: false})
      _active = create_project("visible")

      names = Projects.list_projects_for_sidebar() |> Enum.map(& &1.name)
      refute "hidden" in names
      assert "visible" in names
    end
  end
```

- [ ] **Step 2: Run to confirm failures**

```bash
mix test test/eye_in_the_sky/projects_bookmarks_test.exs
```

Expected: multiple failures — functions not defined yet.

- [ ] **Step 3: Add `list_projects_for_sidebar/0` to `projects.ex`**

In `lib/eye_in_the_sky/projects.ex`, add after `list_projects/0` (after line 22):

```elixir
  @doc """
  Returns active projects ordered for sidebar display:
  bookmarked first, then case-insensitive name, then id for stability.
  """
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

- [ ] **Step 4: Add `set_bookmarked/2` to `projects.ex`**

Add after `delete_project/1` (after line 63):

```elixir
  @doc """
  Sets the bookmarked state of a project. Returns {:ok, project} or {:error, :not_found}.
  """
  def set_bookmarked(project_id, bookmarked) when is_boolean(bookmarked) do
    case get_project(project_id) do
      nil ->
        {:error, :not_found}

      project ->
        project
        |> Project.changeset(%{bookmarked: bookmarked})
        |> Repo.update()
    end
  end
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
mix test test/eye_in_the_sky/projects_bookmarks_test.exs
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky/projects.ex test/eye_in_the_sky/projects_bookmarks_test.exs
git commit -m "feat: add set_bookmarked/2 and list_projects_for_sidebar/0"
```

---

### Task 4: Add `"projects"` PubSub topic to `Events`

**Files:**
- Modify: `lib/eye_in_the_sky/events.ex`

- [ ] **Step 1: Add to the topics table in the moduledoc**

In `lib/eye_in_the_sky/events.ex`, find the topics table in `@moduledoc` (line 11) and add:

```markdown
  | `"projects"`                   | Sidebar                           |
```

- [ ] **Step 2: Add subscribe and broadcast functions**

After `subscribe_settings/0` (around line 78), add:

```elixir
  @doc "Subscribe to project metadata changes (bookmark toggled, etc.)."
  def subscribe_projects, do: sub("projects")

  @doc "A project record was updated. Broadcasts to projects topic."
  def project_updated(project), do: broadcast("projects", {:project_updated, project})
```

- [ ] **Step 3: Verify compilation**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky/events.ex
git commit -m "feat: add projects PubSub topic to Events"
```

---

### Task 5: Wire up Sidebar LiveComponent

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/sidebar.ex`

- [ ] **Step 1: Update `mount/1`**

In `lib/eye_in_the_sky_web/components/sidebar.ex`, replace line 14:

```elixir
    projects = Projects.list_projects()
```

with:

```elixir
    if connected?(socket), do: EyeInTheSky.Events.subscribe_projects()
    projects = Projects.list_projects_for_sidebar()
```

- [ ] **Step 2: Add `handle_event("set_bookmark", ...)`**

Add after the `handle_event("delete_project", ...)` block:

```elixir
  @impl true
  def handle_event("set_bookmark", %{"id" => id, "value" => value}, socket) do
    bookmarked = value == "true"
    {:ok, project} = Projects.set_bookmarked(String.to_integer(id), bookmarked)
    EyeInTheSky.Events.project_updated(project)
    {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
  end
```

- [ ] **Step 3: Add `handle_info({:project_updated, ...})`**

Add after the event handlers:

```elixir
  @impl true
  def handle_info({:project_updated, _project}, socket) do
    {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
  end
```

- [ ] **Step 4: Verify compilation**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/components/sidebar.ex
git commit -m "feat: sidebar subscribes to projects topic and handles bookmark event"
```

---

### Task 6: Add bookmark button to `projects_section.ex`

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/sidebar/projects_section.ex`
- Modify: `test/eye_in_the_sky_web/components/projects_section_test.exs`

- [ ] **Step 1: Write failing component tests**

Append to `test/eye_in_the_sky_web/components/projects_section_test.exs`:

```elixir
  describe "bookmark button" do
    test "bookmark button is present in hover actions for each project" do
      p = build_project()
      html = render_section(%{projects: [p]})

      assert html =~ "set_bookmark"
    end

    test "outline bookmark icon when project is not bookmarked" do
      p = build_project()
      html = render_section(%{projects: [p]})

      assert html =~ ~s(hero-bookmark")
      refute html =~ ~s(hero-bookmark-solid")
    end

    test "solid bookmark icon when project is bookmarked" do
      p = build_project()
      {:ok, p} = Projects.update_project(p, %{bookmarked: true})
      html = render_section(%{projects: [p]})

      assert html =~ ~s(hero-bookmark-solid")
    end

    test "phx-disable-with present on bookmark button" do
      p = build_project()
      html = render_section(%{projects: [p]})

      assert html =~ "phx-disable-with"
    end
  end
```

- [ ] **Step 2: Run to confirm failures**

```bash
mix test test/eye_in_the_sky_web/components/projects_section_test.exs
```

Expected: 4 new failures.

- [ ] **Step 3: Add bookmark `<li>` to the dropdown in `projects_section.ex`**

Find the dropdown `<ul>` that contains the rename and delete items (around line 144). Insert a new `<li>` **before** the delete item:

```heex
                    <li>
                      <button
                        phx-click="set_bookmark"
                        phx-value-id={project.id}
                        phx-value-value={"#{!project.bookmarked}"}
                        phx-target={@myself}
                        phx-disable-with=""
                        class="flex items-center gap-2 text-sm"
                      >
                        <.icon
                          name={if project.bookmarked, do: "hero-bookmark-solid", else: "hero-bookmark"}
                          class="w-3.5 h-3.5"
                        />
                        {if project.bookmarked, do: "Unbookmark", else: "Bookmark"}
                      </button>
                    </li>
```

- [ ] **Step 4: Run tests to confirm all pass**

```bash
mix test test/eye_in_the_sky_web/components/projects_section_test.exs
```

Expected: all tests pass, 0 failures.

- [ ] **Step 5: Full test suite**

```bash
mix test
```

Expected: 0 failures.

- [ ] **Step 6: Compile check**

```bash
mix compile --warnings-as-errors
```

Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web/components/sidebar/projects_section.ex \
        test/eye_in_the_sky_web/components/projects_section_test.exs
git commit -m "feat: add bookmark button to project sidebar dropdown"
```

---

### Task 7: Smoke test in browser

- [ ] **Step 1: Start server**

```bash
PORT=5002 DISABLE_AUTH=true mix phx.server
```

- [ ] **Step 2: Verify behavior**

Navigate to `http://localhost:5002`. Hover a project row, open the ellipsis menu, click Bookmark. Verify:
- The bookmarked project moves to the top of the list immediately.
- The menu item now shows "Unbookmark" with a filled bookmark icon.
- Clicking Unbookmark returns the project to its alphabetical position.
- Opening a second browser tab: bookmarking in one tab updates the list in the other.

- [ ] **Step 3: Stop the server**

`Ctrl+C` to stop.

# Workspace Scope

Documents the scope contract used by workspace-level LiveViews, the ownership validation patterns enforced across the stack, and the canonical queries for workspace-scoped data.

---

## The `Scope` Struct

Workspace routes inject a `%EyeInTheSky.Scope{}` struct into socket assigns via the `WorkspaceLive.Hooks` on_mount hook. It carries two fields that determine which data is visible:

| Field | Values | Meaning |
|-------|--------|---------|
| `:type` | `:workspace` \| `:project` | Which resource owns this scope |
| `:workspace` | `%Workspace{}` | The workspace the current user belongs to |

Project-scoped LiveViews set `type: :project` and additionally carry a `:project` field. Workspace-scoped LiveViews set `type: :workspace` and omit `:project`.

`Sessions.list_sessions_for_scope/1` branches on `scope.type` to return the right set:

```elixir
# workspace scope → all sessions across all projects in the workspace
# project scope   → sessions for that specific project only
def list_sessions_for_scope(%Scope{type: :workspace, workspace: ws}), do: ...
def list_sessions_for_scope(%Scope{type: :project, project: proj}), do: ...
```

---

## `WorkspaceLive.Hooks` — `require_workspace` on_mount

All workspace LiveViews declare:

```elixir
on_mount {EyeInTheSkyWeb.WorkspaceLive.Hooks, :require_workspace}
```

This hook:
1. Looks up the workspace for the current user (`Workspaces.default_workspace_for_user!/1`).
2. Assigns `:workspace` and `:scope` (a `Scope` struct with `type: :workspace`) to the socket.
3. Halts with a redirect to the login page if no user is authenticated.

Do not look up workspaces in `mount/3` — the hook already did it.

---

## Cross-Workspace Ownership Validation

Two enforcement layers prevent a user from operating on resources belonging to another workspace.

### Layer 1 — Server action (pin match)

`WorkspaceLive.Sessions.Actions.create_new_session/2` pins the workspace ID from socket assigns when matching the project returned from the DB:

```elixir
workspace_id = socket.assigns.workspace.id

case Projects.get_project(project_id) do
  {:ok, %{workspace_id: ^workspace_id} = project} ->
    do_create(params, project, socket)

  {:ok, _project} ->
    # project exists but belongs to a different workspace — treat as not found
    {:noreply, put_flash(socket, :error, "Project not found")}
end
```

The pin (`^workspace_id`) makes the match fail silently for foreign projects. The error message is identical to "not found" to avoid leaking information about the existence of other workspaces' projects.

### Layer 2 — Component guard (MapSet lookup)

`NewSessionModal.handle_event("project_changed", ...)` re-validates the incoming `project_id` against the set of projects the component was given:

```elixir
allowed_ids =
  (socket.assigns[:projects] || [])
  |> Enum.map(& &1.id)
  |> then(fn ids ->
    case socket.assigns[:current_project] do
      nil -> ids
      cp  -> [cp.id | ids]
    end
  end)
  |> MapSet.new()

project_path =
  case parse_int(project_id_str) do
    nil -> nil
    id  ->
      if MapSet.member?(allowed_ids, id) do
        case Projects.get_project(id) do
          {:ok, project} -> project.path
          {:error, :not_found} -> nil
        end
      end
  end
```

If `project_id` is not in `allowed_ids`, `project_path` is `nil`, and `list_agents(nil)` returns only global agents — the same result as no project selected. No error is surfaced to the user; the component just degrades gracefully.

---

## Canonical Queries

### Projects scoped to a workspace

```elixir
Projects.list_projects_for_workspace(workspace_id)
# → [%Project{}, ...] ordered case-insensitively by name
```

Use this everywhere a workspace LiveView needs the project dropdown or project list. Never query `Project` directly with a `workspace_id` filter outside this function.

### Sessions scoped to a workspace

```elixir
Sessions.list_sessions_for_scope(socket.assigns.scope)
# → [%Session{}, ...] with :project preloaded
```

Pass the `Scope` struct, not the workspace ID directly. This keeps scope-type branching in one place.

---

## Adding a New Workspace-Scoped LiveView

1. Add the route under the workspace pipeline in `router.ex`.
2. Declare `on_mount {EyeInTheSkyWeb.WorkspaceLive.Hooks, :require_workspace}`.
3. Use `socket.assigns.workspace` (not a mount-time lookup) for the workspace reference.
4. Use `socket.assigns.scope` with the canonical query functions above.
5. For any form that accepts a `project_id`, apply the same pin-match pattern as `Sessions.Actions` — never trust a form-supplied project ID without verifying `workspace_id`.

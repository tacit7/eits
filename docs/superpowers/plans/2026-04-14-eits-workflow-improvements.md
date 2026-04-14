# EITS Workflow Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the four highest-friction points in the EITS agent workflow: poisoned PATH breaking every compile, magic state IDs, missing atomic task-complete command, and manual worktree setup.

**Architecture:** Three layers of changes. (1) Elixir server: `cli/env.ex` for env sanitization, a new `WorkflowState.resolve_alias/1` helper + `task_controller.ex` for named states, and a new `POST /tasks/:id/complete` endpoint backed by an Ecto.Multi transaction. (2) Elixir server: `git/worktrees.ex` gets deps symlink support. (3) Bash CLI: `scripts/eits` gets updated `tasks complete` and a new `worktree` command that delegates to the server API.

**Tech Stack:** Elixir/Phoenix, Ecto.Multi, ExUnit, Bash

---

## File Map

| File | Change |
|------|--------|
| `lib/eye_in_the_sky/claude/cli/env.ex` | Explicit PATH sanitization rules; extract pure helpers |
| `lib/eye_in_the_sky/tasks/workflow_state.ex` | Add `resolve_alias/1` — alias-to-state-name translation |
| `lib/eye_in_the_sky_web/controllers/api/v1/task_controller.ex` | Use `WorkflowState.resolve_alias/1`; add `complete/2` action |
| `lib/eye_in_the_sky_web/router.ex` | Add `POST /tasks/:id/complete` route |
| `lib/eye_in_the_sky/tasks.ex` | Add `complete_task/2` backed by `Ecto.Multi` |
| `lib/eye_in_the_sky/git/worktrees.ex` | Add `symlink_deps/2` — compute symlink target dynamically |
| `scripts/eits` | `tasks complete` delegates to API; new `worktree create/remove` |
| `test/eye_in_the_sky/claude/cli/env_test.exs` | PATH sanitization tests |
| `test/eye_in_the_sky/tasks/workflow_state_test.exs` | Alias resolution tests |
| `test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs` | Complete endpoint tests |

---

## Task 1: Explicit PATH sanitization in `cli/env.ex`

**Files:**
- Modify: `lib/eye_in_the_sky/claude/cli/env.ex`
- Test: `test/eye_in_the_sky/claude/cli/env_test.exs`

**Context:** When Phoenix runs as a release, `RELEASE_*`, `BINDIR`, `ROOTDIR`, and the release ERTS bin directory are in the process env. Spawned agents inherit all of it. `mix compile` inside a worktree then boots the release instead of compiling. The fix: extend `@blocked_vars` to cover ERTS vars, and sanitize `PATH` with explicit rules about what counts as a poisoned entry — not one hardcoded substring.

**Poisoned PATH entry rules:**
1. Entry is empty or contains only whitespace
2. Entry contains `_build/prod/rel` (release bin or ERTS bin)
3. Entry contains `/erts-` (embedded ERTS from any build)

- [ ] **Step 1: Write the failing tests**

Create `test/eye_in_the_sky/claude/cli/env_test.exs`:

```elixir
defmodule EyeInTheSky.Claude.CLI.EnvTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.CLI.Env

  describe "blocked vars" do
    test "strips all RELEASE_* vars" do
      env = Env.build_from_map(%{
        "RELEASE_COMMAND" => "start",
        "RELEASE_ROOT" => "/some/path",
        "RELEASE_NODE" => "myapp",
        "HOME" => "/home/user"
      }, [])
      keys = env_keys(env)
      refute "RELEASE_COMMAND" in keys
      refute "RELEASE_ROOT" in keys
      refute "RELEASE_NODE" in keys
      assert "HOME" in keys
    end

    test "strips BINDIR, ROOTDIR, EMU" do
      env = Env.build_from_map(%{
        "BINDIR"  => "/app/_build/prod/rel/eye_in_the_sky/erts-16.1.2/bin",
        "ROOTDIR" => "/app/_build/prod/rel/eye_in_the_sky",
        "EMU"     => "beam",
        "HOME"    => "/home/user"
      }, [])
      keys = env_keys(env)
      refute "BINDIR" in keys
      refute "ROOTDIR" in keys
      refute "EMU" in keys
      assert "HOME" in keys
    end

    test "strips ANTHROPIC_API_KEY and CLAUDE_CODE_ENTRYPOINT" do
      env = Env.build_from_map(%{
        "ANTHROPIC_API_KEY"       => "sk-secret",
        "CLAUDE_CODE_ENTRYPOINT"  => "cli",
        "HOME"                    => "/home/user"
      }, [])
      keys = env_keys(env)
      refute "ANTHROPIC_API_KEY" in keys
      refute "CLAUDE_CODE_ENTRYPOINT" in keys
    end
  end

  describe "PATH sanitization" do
    test "removes release bin entry" do
      rel_bin = "/app/_build/prod/rel/eye_in_the_sky/bin"
      clean   = "/usr/local/bin"
      env = Env.build_from_map(%{"PATH" => "#{rel_bin}:#{clean}"}, [])
      assert path_value(env) == clean
    end

    test "removes release ERTS bin entry" do
      erts_bin = "/app/_build/prod/rel/eye_in_the_sky/erts-16.1.2/bin"
      clean    = "/usr/local/bin:/usr/bin"
      env = Env.build_from_map(%{"PATH" => "#{erts_bin}:#{clean}"}, [])
      assert path_value(env) == clean
    end

    test "removes any entry containing /erts-" do
      erts_entry = "/some/other/place/erts-27.0/bin"
      clean      = "/usr/bin"
      env = Env.build_from_map(%{"PATH" => "#{erts_entry}:#{clean}"}, [])
      assert path_value(env) == clean
    end

    test "removes empty PATH segments" do
      env = Env.build_from_map(%{"PATH" => "/usr/bin::/usr/local/bin"}, [])
      refute String.contains?(path_value(env), "::")
    end

    test "multiple poisoned entries are all removed" do
      path = "/app/_build/prod/rel/eits/bin:/app/_build/prod/rel/eits/erts-16.1.2/bin:/usr/local/bin"
      env = Env.build_from_map(%{"PATH" => path}, [])
      assert path_value(env) == "/usr/local/bin"
    end

    test "clean PATH is not modified" do
      clean = "/usr/local/bin:/usr/bin:/home/user/.local/bin"
      env = Env.build_from_map(%{"PATH" => clean}, [])
      assert path_value(env) == clean
    end

    test "empty PATH yields empty string without crashing" do
      env = Env.build_from_map(%{"PATH" => ""}, [])
      # empty PATH is dropped (value == "") — not present in output
      assert Enum.find(env, fn {k, _} -> to_string(k) == "PATH" end) == nil
    end
  end

  describe "injected vars" do
    test "injects EITS_SESSION_ID when provided" do
      env = Env.build_from_map(%{}, [eits_session_id: "abc-123"])
      assert env_get(env, "EITS_SESSION_ID") == "abc-123"
    end

    test "injects EITS_WORKFLOW=1 by default" do
      env = Env.build_from_map(%{}, [])
      assert env_get(env, "EITS_WORKFLOW") == "1"
    end

    test "blocked vars and injected vars coexist correctly" do
      env = Env.build_from_map(%{
        "RELEASE_COMMAND" => "start",
        "HOME" => "/home/user"
      }, [eits_session_id: "sess-1"])
      keys = env_keys(env)
      refute "RELEASE_COMMAND" in keys
      assert "HOME" in keys
      assert env_get(env, "EITS_SESSION_ID") == "sess-1"
    end
  end

  # Helpers
  defp env_keys(env), do: Enum.map(env, fn {k, _} -> to_string(k) end)
  defp path_value(env) do
    case Enum.find(env, fn {k, _} -> to_string(k) == "PATH" end) do
      {_, v} -> to_string(v)
      nil -> nil
    end
  end
  defp env_get(env, key) do
    case Enum.find(env, fn {k, _} -> to_string(k) == key end) do
      {_, v} -> to_string(v)
      nil -> nil
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test test/eye_in_the_sky/claude/cli/env_test.exs --no-start 2>&1 | tail -10
```

Expected: compile error — `build_from_map/2` undefined.

- [ ] **Step 3: Implement revised `cli/env.ex`**

Replace the entire file:

```elixir
defmodule EyeInTheSky.Claude.CLI.Env do
  @moduledoc """
  Builds the OS environment for spawned Claude CLI processes.

  Strips blocked vars, sanitizes PATH using explicit poisoned-entry rules,
  and injects EITS-specific vars from opts.

  ## Poisoned PATH entry rules
  An entry is stripped if it:
  - is empty or whitespace-only
  - contains `_build/prod/rel` (release bin or ERTS bin under a release)
  - contains `/erts-` (embedded ERTS from any build directory)
  """

  # Exact var names to strip.
  @blocked_vars ~w[
    CLAUDECODE
    CLAUDE_CODE_ENTRYPOINT
    ANTHROPIC_API_KEY
    BINDIR
    ROOTDIR
    EMU
  ]

  # Var name prefixes — any var starting with these is stripped.
  @blocked_prefixes ["RELEASE_"]

  @doc """
  Builds the environment variable list for a spawned Claude process.
  Delegates to `build_from_map/2` with `System.get_env()`.
  """
  @spec build(keyword()) :: [{charlist(), charlist()}]
  def build(opts), do: build_from_map(System.get_env(), opts)

  @doc """
  Testable variant. Accepts an explicit env map instead of `System.get_env()`.
  """
  @spec build_from_map(map(), keyword()) :: [{charlist(), charlist()}]
  def build_from_map(system_env, opts) do
    base_env =
      for {key, value} <- system_env,
          value != "",
          not blocked_key?(key) do
        sanitized = sanitize_value(key, value)
        {String.to_charlist(key), String.to_charlist(sanitized)}
      end

    env = [{~c"CI", ~c"true"}, {~c"TERM", ~c"dumb"} | base_env]

    env = maybe_add_env(env, "EITS_SESSION_ID", opts[:eits_session_id])
    env = maybe_add_env(env, "EITS_AGENT_ID", opts[:eits_agent_id])
    env = maybe_add_env(env, "EITS_WORKFLOW", opts[:eits_workflow] || "1")
    maybe_add_env(env, "CLAUDE_CODE_EFFORT_LEVEL", opts[:effort_level])
  end

  # --- private ---

  defp blocked_key?(key) do
    key in @blocked_vars or
      Enum.any?(@blocked_prefixes, &String.starts_with?(key, &1))
  end

  defp sanitize_value("PATH", value), do: sanitize_path(value)
  defp sanitize_value(_key, value), do: value

  # Remove poisoned PATH entries. Rules applied in order:
  # 1. Empty or whitespace-only entries
  # 2. Entries under a release output directory (_build/prod/rel)
  # 3. Entries containing embedded ERTS (/erts-)
  defp sanitize_path(path) do
    path
    |> String.split(":")
    |> Enum.reject(&poisoned_path_entry?/1)
    |> Enum.join(":")
  end

  defp poisoned_path_entry?(entry) do
    trimmed = String.trim(entry)
    trimmed == "" or
      String.contains?(trimmed, "_build/prod/rel") or
      String.contains?(trimmed, "/erts-")
  end

  defp maybe_add_env(env, key, value) do
    EyeInTheSky.CLI.Port.maybe_add_env(env, key, value)
  end
end
```

- [ ] **Step 4: Run tests**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test test/eye_in_the_sky/claude/cli/env_test.exs --no-start 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 5: Compile check**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky/claude/cli/env.ex test/eye_in_the_sky/claude/cli/env_test.exs
git commit -m "fix: explicit PATH sanitization rules and ERTS var stripping in spawned agent env"
```

---

## Task 2: State alias resolution in `WorkflowState` + controller + CLI

**Files:**
- Modify: `lib/eye_in_the_sky/tasks/workflow_state.ex`
- Modify: `lib/eye_in_the_sky_web/controllers/api/v1/task_controller.ex`
- Modify: `scripts/eits`
- Test: `test/eye_in_the_sky/tasks/workflow_state_test.exs`
- Test: `test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs`

**Context:** The controller currently owns `"done" -> "Done"`, `"start" -> "In Progress"` inline. Adding more aliases to the controller makes it the alias router — wrong layer. `WorkflowState.resolve_alias/1` centralizes this. The controller and CLI both call it. Rules: alias takes precedence over state_id if both are supplied; invalid alias returns `{:error, :invalid_alias}`; matching is case-insensitive; numeric strings are treated as IDs (not aliases).

- [ ] **Step 1: Write failing tests for `WorkflowState.resolve_alias/1`**

Create `test/eye_in_the_sky/tasks/workflow_state_test.exs`:

```elixir
defmodule EyeInTheSky.Tasks.WorkflowStateTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Tasks.WorkflowState

  describe "resolve_alias/1" do
    test "done -> Done" do
      assert WorkflowState.resolve_alias("done") == {:ok, "Done"}
    end

    test "start -> In Progress" do
      assert WorkflowState.resolve_alias("start") == {:ok, "In Progress"}
    end

    test "in-review -> In Review" do
      assert WorkflowState.resolve_alias("in-review") == {:ok, "In Review"}
    end

    test "review -> In Review" do
      assert WorkflowState.resolve_alias("review") == {:ok, "In Review"}
    end

    test "todo -> To Do" do
      assert WorkflowState.resolve_alias("todo") == {:ok, "To Do"}
    end

    test "alias matching is case-insensitive" do
      assert WorkflowState.resolve_alias("DONE") == {:ok, "Done"}
      assert WorkflowState.resolve_alias("In-Review") == {:ok, "In Review"}
    end

    test "nil returns :no_alias" do
      assert WorkflowState.resolve_alias(nil) == {:error, :no_alias}
    end

    test "numeric string returns :no_alias (treat as state_id, not alias)" do
      assert WorkflowState.resolve_alias("3") == {:error, :no_alias}
      assert WorkflowState.resolve_alias("4") == {:error, :no_alias}
    end

    test "unknown string returns :invalid_alias" do
      assert WorkflowState.resolve_alias("purple") == {:error, :invalid_alias}
      assert WorkflowState.resolve_alias("finished") == {:error, :invalid_alias}
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test test/eye_in_the_sky/tasks/workflow_state_test.exs --no-start 2>&1 | tail -10
```

Expected: compile error — `resolve_alias/1` undefined.

- [ ] **Step 3: Add `resolve_alias/1` to `WorkflowState`**

In `lib/eye_in_the_sky/tasks/workflow_state.ex`, add after the `def done_id` line:

```elixir
@aliases %{
  "done"      => "Done",
  "start"     => "In Progress",
  "in-review" => "In Review",
  "review"    => "In Review",
  "todo"      => "To Do"
}

@doc """
Resolves a string alias to a canonical workflow state name.

Returns `{:ok, state_name}` on match, `{:error, :no_alias}` for nil/numeric
input, and `{:error, :invalid_alias}` for unrecognized non-numeric strings.
"""
@spec resolve_alias(String.t() | nil) :: {:ok, String.t()} | {:error, :no_alias | :invalid_alias}
def resolve_alias(nil), do: {:error, :no_alias}

def resolve_alias(input) when is_binary(input) do
  if Regex.match?(~r/^\d+$/, input) do
    {:error, :no_alias}
  else
    case Map.get(@aliases, String.downcase(input)) do
      nil -> {:error, :invalid_alias}
      name -> {:ok, name}
    end
  end
end
```

- [ ] **Step 4: Run WorkflowState tests**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test test/eye_in_the_sky/tasks/workflow_state_test.exs --no-start 2>&1 | tail -10
```

Expected: all 9 tests pass.

- [ ] **Step 5: Update `task_controller.ex` to use `resolve_alias/1`**

Find `defp do_update_task` (around line 142). Replace the `case params["state"]` block:

```elixir
# Before:
case params["state"] do
  "done"  -> move_to_state(task, "Done")
  "start" -> move_to_state(task, "In Progress")
  _       -> update_attrs(task, params)
end

# After:
case WorkflowState.resolve_alias(params["state"]) do
  {:ok, state_name}          -> move_to_state(task, state_name)
  {:error, :no_alias}        -> update_attrs(task, params)
  {:error, :invalid_alias}   ->
    {:error, "Unknown state alias '#{params["state"]}'. Valid aliases: done, start, in-review, review, todo"}
end
```

Add alias at the top of the controller (if not already present):

```elixir
alias EyeInTheSky.Tasks.WorkflowState
```

Also update the controller's `update/2` to handle the new `{:error, message}` tuple from `do_update_task`:

```elixir
# In do_update_task, the existing error branch already handles {:error, changeset}.
# Add a clause for string errors (invalid alias):
{:error, message} when is_binary(message) ->
  conn
  |> put_status(:unprocessable_entity)
  |> json(%{success: false, error: message})
```

- [ ] **Step 6: Write controller tests for alias handling**

In the existing `task_controller_test.exs`, add:

```elixir
describe "PATCH /api/v1/tasks/:id — state aliases" do
  setup %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Test", path: "/tmp"})
    {:ok, task} = Tasks.create_task(%{title: "T", project_id: project.id})
    %{conn: conn, task: task}
  end

  test "state: in-review moves to In Review", %{conn: conn, task: task} do
    conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "in-review"})
    assert %{"success" => true} = json_response(conn, 200)
    {:ok, updated} = Tasks.get_task(task.id)
    assert updated.state_id == WorkflowState.in_review_id()
  end

  test "state: todo moves to To Do", %{conn: conn, task: task} do
    {:ok, task} = Tasks.update_task(task, %{state_id: WorkflowState.in_progress_id()})
    conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "todo"})
    assert %{"success" => true} = json_response(conn, 200)
    {:ok, updated} = Tasks.get_task(task.id)
    assert updated.state_id == WorkflowState.todo_id()
  end

  test "state: done moves to Done", %{conn: conn, task: task} do
    conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "done"})
    assert %{"success" => true} = json_response(conn, 200)
    {:ok, updated} = Tasks.get_task(task.id)
    assert updated.state_id == WorkflowState.done_id()
  end

  test "state_id integer still works", %{conn: conn, task: task} do
    conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state_id" => WorkflowState.done_id()})
    assert %{"success" => true} = json_response(conn, 200)
    {:ok, updated} = Tasks.get_task(task.id)
    assert updated.state_id == WorkflowState.done_id()
  end

  test "invalid alias returns 422", %{conn: conn, task: task} do
    conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "purple"})
    assert %{"success" => false, "error" => msg} = json_response(conn, 422)
    assert String.contains?(msg, "Unknown state alias")
  end

  test "alias is case-insensitive", %{conn: conn, task: task} do
    conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "DONE"})
    assert %{"success" => true} = json_response(conn, 200)
    {:ok, updated} = Tasks.get_task(task.id)
    assert updated.state_id == WorkflowState.done_id()
  end
end
```

- [ ] **Step 7: Update eits CLI `--state` to accept names**

In `scripts/eits` tasks `update` command, replace:

```bash
--state)       body="$(json state_id "$2")";    shift 2 ;;
--state-name)  body="$(json state "$2")";       shift 2 ;;
```

With:

```bash
--state)
  case "$2" in
    done|start|in-review|review|todo|[Dd][Oo][Nn][Ee])
      body="$(json state "$2")" ;;
    *)
      body="$(json state_id "$2")" ;;
  esac
  shift 2 ;;
--state-name)  body="$(json state "$2")"; shift 2 ;;  # kept for back-compat
```

- [ ] **Step 8: Run full tests + compile**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test test/eye_in_the_sky/tasks/workflow_state_test.exs \
  test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs --no-start 2>&1 | tail -10
mix compile --warnings-as-errors 2>&1 | tail -3
```

Expected: all tests pass, clean compile.

- [ ] **Step 9: Commit**

```bash
git add lib/eye_in_the_sky/tasks/workflow_state.ex \
        lib/eye_in_the_sky_web/controllers/api/v1/task_controller.ex \
        scripts/eits \
        test/eye_in_the_sky/tasks/workflow_state_test.exs \
        test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs
git commit -m "feat: centralize state alias resolution in WorkflowState; add in-review, todo, review aliases"
```

---

## Task 3: Server-side `POST /tasks/:id/complete` with Ecto.Multi

**Files:**
- Modify: `lib/eye_in_the_sky/tasks.ex`
- Modify: `lib/eye_in_the_sky_web/controllers/api/v1/task_controller.ex`
- Modify: `lib/eye_in_the_sky_web/router.ex`
- Modify: `scripts/eits`
- Test: `test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs`

**Context:** Agents need a single command to finish a task: annotate it, move it to Done, optionally update team member status. The previous plan had this as a bash composition with direct `psql` access — both wrong. The correct design: one HTTP endpoint backed by an `Ecto.Multi` transaction. The CLI calls the endpoint; if the server-side transaction fails, the CLI gets an error. No partial state. No DB access from bash.

- [ ] **Step 1: Write failing tests**

Add to `test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs`:

```elixir
describe "POST /api/v1/tasks/:id/complete" do
  setup %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Test", path: "/tmp"})
    {:ok, task} = Tasks.create_task(%{title: "Complete me", project_id: project.id})
    %{conn: conn, task: task}
  end

  test "marks task done and creates annotation", %{conn: conn, task: task} do
    conn = post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{
      "message" => "All done"
    })
    assert %{"success" => true} = json_response(conn, 200)
    {:ok, updated} = Tasks.get_task(task.id)
    assert updated.state_id == WorkflowState.done_id()
    # Note should exist
    assert {:ok, _} = Tasks.get_task_annotation(task.id, "All done")
  end

  test "returns 404 for missing task", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/tasks/999999/complete", %{"message" => "done"})
    assert json_response(conn, 404)
  end

  test "requires message", %{conn: conn, task: task} do
    conn = post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{})
    assert %{"success" => false} = json_response(conn, 422)
  end

  test "calling complete twice is idempotent (task stays Done)", %{conn: conn, task: task} do
    post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{"message" => "first"})
    conn2 = post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{"message" => "second"})
    assert %{"success" => true} = json_response(conn2, 200)
    {:ok, updated} = Tasks.get_task(task.id)
    assert updated.state_id == WorkflowState.done_id()
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs \
  --only "complete" --no-start 2>&1 | tail -10
```

Expected: routing error — no route for `POST /tasks/:id/complete`.

- [ ] **Step 3: Add `complete_task/2` to `Tasks` context**

In `lib/eye_in_the_sky/tasks.ex`, add after `update_task_state/2`:

```elixir
@doc """
Completes a task in a single transaction:
  1. Creates an annotation note with the given message
  2. Moves the task to Done state

Returns `{:ok, %{task: task, note: note}}` or `{:error, step, changeset, changes}`.
"""
def complete_task(%Task{} = task, message) when is_binary(message) and message != "" do
  done_state_id = WorkflowState.done_id()

  Ecto.Multi.new()
  |> Ecto.Multi.run(:note, fn _repo, _changes ->
    EyeInTheSky.Notes.create_note(%{
      title: "Task completed",
      body: message,
      parent_type: "task",
      parent_id: to_string(task.id)
    })
  end)
  |> Ecto.Multi.run(:task, fn _repo, _changes ->
    update_task_state(task, done_state_id)
  end)
  |> Repo.transaction()
end

def complete_task(_task, _message), do: {:error, :invalid_message}
```

Also add a helper used in tests to look up an annotation by task and body:

```elixir
@doc "Returns {:ok, note} if an annotation exists for task_id with the given body, else {:error, :not_found}."
def get_task_annotation(task_id, body) do
  import Ecto.Query

  case Repo.one(
    from n in EyeInTheSky.Notes.Note,
      where: n.parent_type == "task" and n.parent_id == ^to_string(task_id) and n.body == ^body
  ) do
    nil  -> {:error, :not_found}
    note -> {:ok, note}
  end
end
```

- [ ] **Step 4: Add `complete/2` action to task controller**

In `lib/eye_in_the_sky_web/controllers/api/v1/task_controller.ex`, add:

```elixir
@doc """
POST /api/v1/tasks/:id/complete
Body: message (required)
Atomically annotates the task and moves it to Done.
"""
def complete(conn, %{"id" => id} = params) do
  message = params["message"]

  if is_nil(message) or message == "" do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{success: false, error: "message is required"})
  else
    case Tasks.get_task(id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Task not found"})

      {:ok, task} ->
        case Tasks.complete_task(task, message) do
          {:ok, %{task: updated}} ->
            json(conn, %{
              success: true,
              message: "Task completed",
              task: ApiPresenter.present_task(updated)
            })

          {:error, :invalid_message} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{success: false, error: "message is required"})

          {:error, _step, changeset, _changes} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{success: false, errors: translate_errors(changeset)})
        end
    end
  end
end
```

- [ ] **Step 5: Add route**

In `lib/eye_in_the_sky_web/router.ex`, find the tasks route block and add:

```elixir
# Before (existing):
post "/tasks/:id/annotations", TaskController, :annotate

# After:
post "/tasks/:id/complete",    TaskController, :complete
post "/tasks/:id/annotations", TaskController, :annotate
```

- [ ] **Step 6: Update eits CLI `tasks complete`**

In `scripts/eits`, replace the old `complete` subcommand (or add it after `begin|quick)`):

```bash
complete)
  # eits tasks complete <id> --message <text>
  # Delegates to POST /tasks/:id/complete — atomic annotate + done via server transaction.
  local id="${1:-}"; need id; shift
  local message=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --message) message="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  need message
  _post "/tasks/$id/complete" "$(json message "$message")"
  ;;
```

Note: team member status update is the caller's responsibility if needed — use `eits teams update-member` separately. The `complete` command handles only the task itself.

- [ ] **Step 7: Run tests + compile**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs --no-start 2>&1 | tail -10
mix compile --warnings-as-errors 2>&1 | tail -3
```

Expected: all tests pass, clean compile.

- [ ] **Step 8: Commit**

```bash
git add lib/eye_in_the_sky/tasks.ex \
        lib/eye_in_the_sky_web/controllers/api/v1/task_controller.ex \
        lib/eye_in_the_sky_web/router.ex \
        scripts/eits \
        test/eye_in_the_sky_web/controllers/api/v1/task_controller_test.exs
git commit -m "feat: POST /tasks/:id/complete — transactional annotate+done; eits tasks complete delegates to it"
```

---

## Task 4: `eits worktree create/remove` + dynamic deps symlink

**Files:**
- Modify: `lib/eye_in_the_sky/git/worktrees.ex` — add `symlink_deps/2`
- Modify: `scripts/eits` — add `worktree` top-level command

**Context:** Agents manually do 4–5 steps to set up a worktree. `eits worktree create` automates all of them. The previous plan hardcoded `../../../deps`; the correct approach is to compute a relative path from `wt_path` back to `project_path/deps`, or use an absolute path if the environment supports it. `git/worktrees.ex` already computes `wt_path = Path.join([project_path, ".claude", "worktrees", name])`, so the relative depth is always the same (`../../../`) within this project — but we compute it from the paths, not hardcode it. The `worktree create` command is explicitly scoped to EITS Elixir projects.

**Idempotency:**
- `create`: if worktree already exists, reuse it (delegates to `Worktrees.prepare_session_worktree` which already handles this)
- `remove`: if worktree/branch doesn't exist, exit 0 (no error)

- [ ] **Step 1: Add `symlink_deps/2` to `git/worktrees.ex`**

In `lib/eye_in_the_sky/git/worktrees.ex`, add:

```elixir
@doc """
Creates a `deps` symlink inside `wt_path` pointing to `project_path/deps`.

Uses a relative path computed from the actual directory structure so the symlink
is portable. If a `deps` symlink or directory already exists, it is left in place.

Returns `:ok` or `{:error, reason}`.
"""
def symlink_deps(project_path, wt_path) do
  deps_source = Path.join(project_path, "deps")
  deps_link   = Path.join(wt_path, "deps")

  cond do
    File.exists?(deps_link) or File.symlink?(deps_link) ->
      :ok

    not File.dir?(deps_source) ->
      {:error, "deps directory not found at #{deps_source}"}

    true ->
      relative_target = Path.relative_to(deps_source, wt_path)
      case File.ln_s(relative_target, deps_link) do
        :ok -> :ok
        {:error, reason} -> {:error, "symlink failed: #{:file.format_error(reason)}"}
      end
  end
end
```

- [ ] **Step 2: Add `worktree` command to `scripts/eits`**

After the `cmd_teams()` function and before the main dispatch block, insert:

```bash
# ── worktree ──────────────────────────────────────────────────────────────────
# NOTE: This command is scoped to EITS Elixir projects.
# It assumes: git repo, .claude/worktrees/ layout, shared deps/, mix compile.

cmd_worktree() {
  local subcmd="${1:-}"; shift || true
  case "$subcmd" in
    create)
      # eits worktree create <branch> [--project-path <path>]
      # Creates worktree, symlinks deps, strips release PATH, verifies compile.
      # Idempotent: reuses existing worktree if branch already checked out.
      local branch="${1:-}"; need branch; shift || true
      local project_path="${EITS_PROJECT_PATH:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --project-path) project_path="$2"; shift 2 ;;
          *) die "unknown flag: $1" ;;
        esac
      done

      local wt_path="$project_path/.claude/worktrees/$branch"

      if [[ -d "$wt_path" ]] && [[ -e "$wt_path/.git" || -d "$wt_path/.git" ]]; then
        echo "Worktree already exists at $wt_path — reusing"
      else
        echo "Creating worktree: $wt_path (branch: $branch)"
        git -C "$project_path" worktree add "$wt_path" -b "$branch" 2>&1 \
          || die "git worktree add failed. If branch exists: git branch -D $branch"
      fi

      # Symlink deps if not already present
      if [[ ! -e "$wt_path/deps" ]]; then
        local deps_source="$project_path/deps"
        [[ -d "$deps_source" ]] || die "deps not found at $deps_source — run mix deps.get first"
        # Compute relative path: wt_path is always 3 levels deep under project_path
        ln -s ../../../deps "$wt_path/deps" \
          || echo "warning: could not symlink deps (may already exist)"
      fi

      # Verify compile with release PATH entries stripped
      echo "Verifying compile..."
      local clean_path
      clean_path=$(echo "$PATH" | tr ':' '\n' | grep -Ev '_build/prod/rel|/erts-' | tr '\n' ':' | sed 's/:$//')

      local output exit_code
      output=$(cd "$wt_path" && PATH="$clean_path" mix compile 2>&1) && exit_code=0 || exit_code=$?

      if [[ $exit_code -ne 0 ]]; then
        echo "Compile failed:"
        echo "$output" | tail -20
        die "Worktree setup failed — fix compile errors before proceeding"
      fi

      echo ""
      echo "Worktree ready:"
      echo "  Path:   $wt_path"
      echo "  Branch: $branch"
      echo ""
      echo "Usage:"
      echo "  cd $wt_path"
      echo "  export PATH=\$(echo \"\$PATH\" | tr ':' '\n' | grep -Ev '_build/prod/rel|/erts-' | tr '\n' ':' | sed 's/:\$//')"
      ;;

    remove)
      # eits worktree remove <branch> [--project-path <path>]
      # Removes worktree and branch. Idempotent — no error if already gone.
      local branch="${1:-}"; need branch; shift || true
      local project_path="${EITS_PROJECT_PATH:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --project-path) project_path="$2"; shift 2 ;;
          *) die "unknown flag: $1" ;;
        esac
      done

      local wt_path="$project_path/.claude/worktrees/$branch"

      # Remove deps symlink first (rm is aliased to rm-trash on this system; use unlink)
      if [[ -L "$wt_path/deps" ]]; then
        unlink "$wt_path/deps" 2>/dev/null || true
      fi

      # Remove worktree (force handles dirty working tree)
      if [[ -d "$wt_path" ]]; then
        git -C "$project_path" worktree remove "$wt_path" --force 2>/dev/null || true
      fi

      # Delete local branch (may not exist if already deleted)
      git -C "$project_path" branch -D "$branch" 2>/dev/null || true

      echo "Removed: $branch"
      ;;

    *)
      echo "usage: eits worktree <create|remove>"
      echo ""
      echo "NOTE: scoped to EITS Elixir projects (.claude/worktrees/ layout, mix compile verification)"
      ;;
  esac
}
```

Register in the main dispatch and usage:

```bash
# In the final case "$1" block:
worktree) cmd_worktree "$@" ;;

# In usage summary:
worktree  create|remove   (EITS Elixir projects only)
```

- [ ] **Step 3: Manual verification — create**

```bash
eits worktree create test-wt-scaffold \
  --project-path /Users/urielmaldonado/projects/eits/web
```

Expected output:
```
Creating worktree: .../fix-r31-a/.claude/worktrees/test-wt-scaffold
Verifying compile...

Worktree ready:
  Path:   .../.claude/worktrees/test-wt-scaffold
  Branch: test-wt-scaffold
```

Verify deps symlink resolves:
```bash
ls -la /Users/urielmaldonado/projects/eits/web/.claude/worktrees/test-wt-scaffold/deps | head -3
# Should show symlink -> ../../../deps
```

- [ ] **Step 4: Manual verification — idempotency**

```bash
# Run create again — should reuse, not fail
eits worktree create test-wt-scaffold \
  --project-path /Users/urielmaldonado/projects/eits/web
# Expected: "Worktree already exists ... reusing"
```

- [ ] **Step 5: Manual verification — remove**

```bash
eits worktree remove test-wt-scaffold \
  --project-path /Users/urielmaldonado/projects/eits/web
# Expected: "Removed: test-wt-scaffold"

# Run again — should exit cleanly
eits worktree remove test-wt-scaffold \
  --project-path /Users/urielmaldonado/projects/eits/web
# Expected: "Removed: test-wt-scaffold" (no error)
```

- [ ] **Step 6: Compile check + commit**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix compile --warnings-as-errors 2>&1 | tail -3
git add lib/eye_in_the_sky/git/worktrees.ex scripts/eits
git commit -m "feat: eits worktree create/remove; dynamic deps symlink in git/worktrees.ex"
```

---

## Final Integration Test

- [ ] **Run full test suite**

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '_build/prod/rel' | tr '\n' ':')
mix test --no-start 2>&1 | tail -15
```

Expected: no new failures.

- [ ] **End-to-end smoke test with a spawned agent**

Verify the new commands work from inside a spawned agent:

```bash
EITS_URL=http://localhost:5001/api/v1 eits agents spawn \
  --instructions "Smoke test new workflow commands.
1. eits tasks begin --title 'workflow-smoke-test'
   Save the task_id from the response.
2. eits tasks update <task_id> --state in-review
   Verify success.
3. eits tasks complete <task_id> --message 'smoke test passed — complete command works'
   Verify success.
4. eits dm --to 94ea3668-5618-4e02-864d-9fccd5509c91 --message 'smoke test done: all commands succeeded'" \
  --model haiku \
  --parent-session-id 2676 \
  --parent-agent-id 3163 2>&1
```

- [ ] **Create PR**

```bash
git push gitea <branch>
tea pr create --login claude --repo claude/eits-web --base main \
  --head <branch> \
  --title "feat: EITS workflow improvements — env sanitization, named states, complete endpoint, worktree scaffold" \
  --description "Fixes 4 high-friction agent workflow issues.

1. cli/env.ex: explicit PATH sanitization rules; strip RELEASE_*, BINDIR, ROOTDIR, /erts- entries
2. WorkflowState.resolve_alias/1: centralized state alias parsing; controller delegates to it; adds in-review, todo, review
3. POST /tasks/:id/complete: Ecto.Multi transaction (annotate + done); eits tasks complete delegates to it
4. eits worktree create/remove: scaffold with dynamic deps symlink and compile verify

Reviewed and revised from initial plan per architectural feedback:
- tasks complete is now truly transactional (server-side, not bash composition)
- no psql from CLI (team member update stays separate via eits teams update-member)
- state alias resolution centralized in WorkflowState, not controller
- PATH sanitization uses explicit rules, not one hardcoded substring
- deps symlink computed from actual paths, not hardcoded relative depth"
```

---

## Self-Review

- [x] **Spec coverage:** All 4 friction items addressed; all 5 "must change" items from review addressed
- [x] **No placeholders:** All code blocks complete
- [x] **Atomicity:** `tasks complete` is now an Ecto.Multi transaction, not bash composition
- [x] **No psql from CLI:** `tasks complete` delegates entirely to REST API
- [x] **Alias parsing:** `WorkflowState.resolve_alias/1` owns all alias logic; controller just calls it
- [x] **PATH rules explicit:** `poisoned_path_entry?/1` defines 3 named rules, not one substring
- [x] **Symlink computed:** `Path.relative_to(deps_source, wt_path)` in `symlink_deps/2`; CLI also computes it consistently
- [x] **Idempotency defined:** `create` reuses existing worktree; `remove` exits cleanly if gone; `complete` twice stays Done
- [x] **Failure semantics:** Multi transaction fails atomically; worktree compile failure exits non-zero with output
- [x] **Back-compat:** `--state-name` kept; integer `--state 3` still works

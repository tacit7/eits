# Spawn Endpoint Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `POST /api/v1/agents` into a clean validation pipeline with structured error codes, parent ID DB validation, and a thin `create/2` controller action.

**Architecture:** Extract validation into composable private helpers wired into a `with` pipeline. Controller becomes orchestration-only. Tests cover each error code and the success path via HTTP.

**Tech Stack:** Elixir/Phoenix, Ecto, ExUnit ConnCase, `EyeInTheSkyWeb.Factory`, `MockCLI` (already configured for test env via `config/test.exs`)

**Spec:** `docs/superpowers/specs/2026-03-15-spawn-endpoint-improvements-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/eye_in_the_sky_web_web/controllers/api/v1/agent_controller.ex` | Modify | Add `Sessions` alias; add private helpers; refactor `create/2`; update `maybe_join_team/4` |
| `test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs` | Create | HTTP-level tests for all error codes and success path |

---

## Chunk 1: Test File + Validation Error Tests

### Task 1: Create test file with module setup

**Files:**
- Create: `test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs`

- [ ] **Step 1.0: Check if test file already exists**

```bash
ls test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs 2>/dev/null && echo "EXISTS" || echo "NOT FOUND"
```

If it exists, read it first (`Read` tool) and merge the new tests into the existing module rather than overwriting.

- [ ] **Step 1.1: Create test file**

```elixir
defmodule EyeInTheSkyWebWeb.Api.V1.AgentControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  import EyeInTheSkyWeb.Factory

  @valid_params %{
    "instructions" => "Do the thing",
    "model"        => "haiku",
    "project_path" => "/tmp"
  }

  defp post_spawn(conn, params) do
    post(conn, ~p"/api/v1/agents", params)
  end
end
```

- [ ] **Step 1.2: Verify file compiles**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```
Expected: no errors.

---

### Task 2: Test — `missing_required` when instructions absent

- [ ] **Step 2.1: Add failing test**

```elixir
describe "POST /api/v1/agents validation" do
  test "returns missing_required when instructions absent", %{conn: conn} do
    conn = post_spawn(conn, Map.delete(@valid_params, "instructions"))
    resp = json_response(conn, 400)
    assert resp["error_code"] == "missing_required"
    assert resp["message"] =~ "instructions"
  end

  test "returns missing_required when instructions is empty string", %{conn: conn} do
    conn = post_spawn(conn, Map.put(@valid_params, "instructions", ""))
    resp = json_response(conn, 400)
    assert resp["error_code"] == "missing_required"
  end

  test "returns missing_required when instructions is whitespace-only", %{conn: conn} do
    conn = post_spawn(conn, Map.put(@valid_params, "instructions", "   "))
    resp = json_response(conn, 400)
    assert resp["error_code"] == "missing_required"
  end
end
```

- [ ] **Step 2.2: Run test — verify it fails**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -20
```
Expected: FAILED — current endpoint returns `%{"error" => "..."}`, not `%{"error_code" => "..."}`.

---

### Task 3: Test — `instructions_too_long`

- [ ] **Step 3.1: Add test inside the `describe` block**

```elixir
test "returns instructions_too_long when over 32000 chars", %{conn: conn} do
  conn = post_spawn(conn, Map.put(@valid_params, "instructions", String.duplicate("a", 32_001)))
  resp = json_response(conn, 400)
  assert resp["error_code"] == "instructions_too_long"
end
```

- [ ] **Step 3.2: Run — verify failure**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -20
```

---

### Task 4: Test — `invalid_model`

- [ ] **Step 4.1: Add tests**

```elixir
test "returns invalid_model for unknown model", %{conn: conn} do
  conn = post_spawn(conn, Map.put(@valid_params, "model", "gpt-4"))
  resp = json_response(conn, 400)
  assert resp["error_code"] == "invalid_model"
end
```

- [ ] **Step 4.2: Run — verify failure**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -20
```

---

### Task 5: Test — `invalid_parameter` for non-integer parent IDs

- [ ] **Step 5.1: Add tests**

```elixir
test "returns invalid_parameter when parent_agent_id is non-integer string", %{conn: conn} do
  conn = post_spawn(conn, Map.put(@valid_params, "parent_agent_id", "abc"))
  resp = json_response(conn, 400)
  assert resp["error_code"] == "invalid_parameter"
  assert resp["message"] =~ "parent_agent_id"
end

test "returns invalid_parameter when parent_session_id is a float string", %{conn: conn} do
  conn = post_spawn(conn, Map.put(@valid_params, "parent_session_id", "1.5"))
  resp = json_response(conn, 400)
  assert resp["error_code"] == "invalid_parameter"
  assert resp["message"] =~ "parent_session_id"
end
```

- [ ] **Step 5.3: Add test for absent parent IDs (omitting the field entirely must succeed)**

```elixir
test "succeeds when parent_agent_id is absent", %{conn: conn} do
  conn = post_spawn(conn, @valid_params)
  assert json_response(conn, 201)["success"] == true
end

test "succeeds when parent_session_id is absent", %{conn: conn} do
  conn = post_spawn(conn, @valid_params)
  assert json_response(conn, 201)["success"] == true
end
```

> These are passing tests — absent parent IDs are valid. Run them after the implementation is in to confirm the nil clause of `coerce_parent_id/2` is wired correctly.

- [ ] **Step 5.4: Run — verify failures**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -20
```

---

### Task 6: Test — `parent_not_found`

- [ ] **Step 6.1: Add tests**

```elixir
test "returns parent_not_found when parent_agent_id does not exist", %{conn: conn} do
  conn = post_spawn(conn, Map.put(@valid_params, "parent_agent_id", "999999"))
  resp = json_response(conn, 400)
  assert resp["error_code"] == "parent_not_found"
  assert resp["message"] =~ "parent_agent_id"
end

test "returns parent_not_found when parent_session_id does not exist", %{conn: conn} do
  conn = post_spawn(conn, Map.put(@valid_params, "parent_session_id", "999999"))
  resp = json_response(conn, 400)
  assert resp["error_code"] == "parent_not_found"
  assert resp["message"] =~ "parent_session_id"
end

test "accepts valid parent_agent_id that exists in DB", %{conn: conn} do
  agent = create_agent()
  conn = post_spawn(conn, Map.put(@valid_params, "parent_agent_id", to_string(agent.id)))
  assert json_response(conn, 201)["success"] == true
end
```

- [ ] **Step 6.2: Run — verify failures**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -20
```

---

### Task 7: Test — `team_not_found`

- [ ] **Step 7.1: Add test**

```elixir
test "returns team_not_found when team_name does not exist", %{conn: conn} do
  conn = post_spawn(conn, Map.put(@valid_params, "team_name", "nonexistent-team"))
  resp = json_response(conn, 400)
  assert resp["error_code"] == "team_not_found"
  assert resp["message"] =~ "nonexistent-team"
end
```

- [ ] **Step 7.2: Run — verify failure**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -20
```

---

### Task 8: Test — success path response shape

- [ ] **Step 8.1: Add test**

```elixir
describe "POST /api/v1/agents success" do
  test "returns 201 with agent_id, session_id, session_uuid", %{conn: conn} do
    conn = post_spawn(conn, @valid_params)
    resp = json_response(conn, 201)

    assert resp["success"] == true
    assert resp["message"] == "Agent spawned"
    assert is_binary(resp["agent_id"])
    assert is_integer(resp["session_id"])
    assert is_binary(resp["session_uuid"])
  end

  test "defaults model to haiku when absent", %{conn: conn} do
    conn = post_spawn(conn, Map.delete(@valid_params, "model"))
    assert json_response(conn, 201)["success"] == true
  end
end
```

- [ ] **Step 8.2: Run — verify failures**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -20
```

- [ ] **Step 8.3: Commit test file**

```bash
git add test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs
git commit -m "test: add failing tests for spawn endpoint validation pipeline"
```

---

## Chunk 2: Implement Validation Helpers

### Task 9: Add `Sessions` alias and `coerce_parent_id/2`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/controllers/api/v1/agent_controller.ex`

- [ ] **Step 9.1: Add `Sessions` to the alias line**

Find:
```elixir
alias EyeInTheSkyWeb.{Agents, Claude.AgentManager, Teams}
```

Replace with:
```elixir
alias EyeInTheSkyWeb.{Agents, Claude.AgentManager, Sessions, Teams}
```

- [ ] **Step 9.2: Add `coerce_parent_id/2` at the bottom of the private functions section**

```elixir
defp coerce_parent_id(nil, _field), do: {:ok, nil}
defp coerce_parent_id("", _field), do: {:ok, nil}
defp coerce_parent_id(val, _field) when is_integer(val), do: {:ok, val}

defp coerce_parent_id(val, field) when is_binary(val) do
  case Integer.parse(val) do
    {int, ""} -> {:ok, int}
    _         -> {:error, "invalid_parameter", "#{field} must be an integer"}
  end
end

defp coerce_parent_id(_val, field),
  do: {:error, "invalid_parameter", "#{field} must be an integer"}
```

- [ ] **Step 9.3: Compile**

```bash
mix compile
```
Expected: no errors.

---

### Task 10: Add `validate_instructions/1`

- [ ] **Step 10.1: Add helper**

```elixir
defp validate_instructions(nil),
  do: {:error, "missing_required", "instructions is required"}

defp validate_instructions(val) when is_binary(val) do
  trimmed = String.trim(val)

  cond do
    trimmed == "" ->
      {:error, "missing_required", "instructions is required"}

    String.length(trimmed) > 32_000 ->
      {:error, "instructions_too_long", "instructions exceeds 32000 character limit"}

    true ->
      {:ok, trimmed}
  end
end
```

- [ ] **Step 10.2: Compile**

```bash
mix compile
```

---

### Task 11: Add `validate_model/1`

> **Note:** `@valid_models ~w(haiku sonnet opus)` already exists as a module attribute in `agent_controller.ex`. Do NOT add it again — `validate_model/1` uses it as-is.

- [ ] **Step 11.1: Add helper (uses existing `@valid_models` module attribute)**

```elixir
defp validate_model(model) when model in @valid_models, do: {:ok, model}

defp validate_model(_model),
  do: {:error, "invalid_model", "invalid model; must be one of: #{Enum.join(@valid_models, ", ")}"}
```

- [ ] **Step 11.2: Compile**

```bash
mix compile
```

---

### Task 12: Add `validate_parent_agent/1` and `validate_parent_session/1`

- [ ] **Step 12.1: Add helpers**

```elixir
defp validate_parent_agent(nil), do: {:ok, nil}

defp validate_parent_agent(id) do
  case Agents.get_agent(id) do
    {:ok, _}             -> {:ok, id}
    {:error, :not_found} -> {:error, "parent_not_found", "parent_agent_id #{id} does not exist"}
  end
end

defp validate_parent_session(nil), do: {:ok, nil}

defp validate_parent_session(id) do
  case Sessions.get_session(id) do
    {:ok, _}             -> {:ok, id}
    {:error, :not_found} -> {:error, "parent_not_found", "parent_session_id #{id} does not exist"}
  end
end
```

- [ ] **Step 12.2: Compile**

```bash
mix compile
```

---

### Task 13: Add `validate_params/1`

- [ ] **Step 13.1: Add helper**

```elixir
defp validate_params(params) do
  model = params["model"] || "haiku"

  with {:ok, instructions}      <- validate_instructions(params["instructions"]),
       {:ok, _}                 <- validate_model(model),
       {:ok, parent_agent_id}   <- coerce_parent_id(params["parent_agent_id"], "parent_agent_id"),
       {:ok, parent_session_id} <- coerce_parent_id(params["parent_session_id"], "parent_session_id"),
       {:ok, _}                 <- validate_parent_agent(parent_agent_id),
       {:ok, _}                 <- validate_parent_session(parent_session_id) do
    {:ok,
     Map.merge(params, %{
       "instructions"      => instructions,
       "model"             => model,
       "parent_agent_id"   => parent_agent_id,
       "parent_session_id" => parent_session_id
     })}
  end
end
```

- [ ] **Step 13.2: Compile**

```bash
mix compile
```

---

### Task 14: Add `resolve_team/1`

- [ ] **Step 14.1: Add helper**

```elixir
defp resolve_team(params) do
  case params["team_name"] do
    name when name in [nil, ""] ->
      {:ok, nil}

    name ->
      case Teams.get_team_by_name(name) do
        nil  -> {:error, "team_not_found", "team not found: #{name}"}
        team -> {:ok, team}
      end
  end
end
```

- [ ] **Step 14.2: Compile**

```bash
mix compile
```

---

### Task 15: Add `apply_team_context/3`, `build_spawn_opts/2`, `build_response/4`

- [ ] **Step 15.1: Add `apply_team_context/3`**

```elixir
defp apply_team_context(instructions, nil, _member_name), do: instructions

defp apply_team_context(instructions, team, member_name) do
  instructions <> "\n\n" <> build_team_context(team, member_name)
end
```

- [ ] **Step 15.2: Add `build_spawn_opts/2`**

```elixir
defp build_spawn_opts(params, _team) do
  [
    instructions:      params["instructions"],
    model:             params["model"],
    agent_type:        params["provider"] || "claude",
    project_id:        parse_int(params["project_id"], nil),
    project_path:      params["project_path"],
    description:       String.slice(params["instructions"] || "Agent session", 0, 250),
    worktree:          params["worktree"],
    effort_level:      params["effort_level"],
    parent_agent_id:   params["parent_agent_id"],
    parent_session_id: params["parent_session_id"],
    agent:             params["agent"]
  ]
end
```

- [ ] **Step 15.3: Add `build_response/4`**

```elixir
defp build_response(agent, session, nil, _member_name) do
  %{
    success:      true,
    message:      "Agent spawned",
    agent_id:     agent.uuid,
    session_id:   session.id,
    session_uuid: session.uuid
  }
end

defp build_response(agent, session, team, member_name) do
  %{
    success:      true,
    message:      "Agent spawned",
    agent_id:     agent.uuid,
    session_id:   session.id,
    session_uuid: session.uuid,
    team_id:      team.id,
    team_name:    team.name,
    member_name:  member_name
  }
end
```

- [ ] **Step 15.4: Compile**

```bash
mix compile
```
Expected: no errors.

- [ ] **Step 15.5: Commit helpers**

```bash
git add lib/eye_in_the_sky_web_web/controllers/api/v1/agent_controller.ex
git commit -m "feat: add spawn endpoint validation helpers"
```

---

## Chunk 3: Refactor `create/2` and Update `maybe_join_team/4`

### Task 16: Replace `create/2` with `with` pipeline

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/controllers/api/v1/agent_controller.ex` — replace the `create/2` function body

- [ ] **Step 16.1: Delete the entire `create/2` body (the `cond` block) and replace with:**

```elixir
def create(conn, params) do
  with {:ok, params} <- validate_params(params),
       {:ok, team}   <- resolve_team(params) do
    instructions = apply_team_context(params["instructions"], team, params["member_name"])
    opts = build_spawn_opts(%{params | "instructions" => instructions}, team)

    case AgentManager.create_agent(opts) do
      {:ok, %{agent: agent, session: session}} ->
        maybe_join_team(team, agent, session, params["member_name"])
        conn |> put_status(:created) |> json(build_response(agent, session, team, params["member_name"]))

      {:error, reason} ->
        require Logger
        Logger.error("Agent spawn failed: #{inspect(reason)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error_code: "spawn_failed", message: "Agent could not be started"})
    end
  else
    {:error, code, message} ->
      conn |> put_status(:bad_request) |> json(%{error_code: code, message: message})
  end
end
```

- [ ] **Step 16.2: Compile**

```bash
mix compile
```
Expected: no errors.

---

### Task 17: Update `maybe_join_team/4` to log failures

- [ ] **Step 17.1: Replace the non-nil clause of `maybe_join_team/4`**

Find:
```elixir
defp maybe_join_team(team, agent, session, member_name) do
  Teams.join_team(%{
    team_id: team.id,
    agent_id: agent.id,
    session_id: session.id,
    name: member_name || agent.uuid,
    role: member_name || "agent",
    status: "active"
  })
end
```

Replace with:
```elixir
defp maybe_join_team(team, agent, session, member_name) do
  result =
    Teams.join_team(%{
      team_id: team.id,
      agent_id: agent.id,
      session_id: session.id,
      name: member_name || agent.uuid,
      role: member_name || "agent",
      status: "active"
    })

  case result do
    {:ok, _} ->
      :ok

    {:error, reason} ->
      require Logger

      Logger.warning(
        "Team join failed: agent_id=#{agent.id} team_id=#{team.id} reason=#{inspect(reason)}"
      )

      :ok

    _ ->
      :ok
  end
end
```

- [ ] **Step 17.2: Compile**

```bash
mix compile
```

- [ ] **Step 17.3: Run agent controller tests — expect all to pass**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/agent_controller_test.exs --seed 0 2>&1 | tail -30
```
Expected: all green. If failures, fix before proceeding.

- [ ] **Step 17.4: Run full test suite — verify no regressions**

```bash
mix test --exclude integration 2>&1 | tail -20
```
Expected: all passing.

- [ ] **Step 17.5: Compile with warnings as errors**

```bash
mix compile --warnings-as-errors
```
Expected: clean.

- [ ] **Step 17.6: Commit**

```bash
git add lib/eye_in_the_sky_web_web/controllers/api/v1/agent_controller.ex
git commit -m "refactor: spawn endpoint validation pipeline with structured error codes"
```

---

## Chunk 4: Final Verification

### Task 18: Log commits in EITS

- [ ] **Step 18.1: Get commit hashes**

```bash
git log --oneline -3
```

- [ ] **Step 18.2: Log each commit**

```bash
eits commits create --hash <feat-helpers-hash>
eits commits create --hash <refactor-hash>
```

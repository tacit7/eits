# Spawn Endpoint Improvements — Design Spec

**Date:** 2026-03-15
**Endpoint:** `POST /api/v1/agents`
**File:** `lib/eye_in_the_sky_web_web/controllers/api/v1/agent_controller.ex`

---

## Problem

The spawn endpoint has two issues:

1. **Contract:** No structured error codes; parent IDs unvalidated; generic failure message loses reason; callers are agents that need actionable error detail.
2. **Code quality:** `create/2` is a deeply nested `cond` block mixing validation, team resolution, and spawn logic. No separation of concerns.

---

## Approach

Extract a validation pipeline, add parent ID DB checks, and return structured errors with codes. The `create/2` action becomes a clean `with` pipeline.

---

## `parse_int`

`parse_int/2` already exists in `ControllerHelpers`. It accepts an integer (returns it as-is) or a binary string. For strings it uses `Integer.parse/1` — any result where the remainder is non-empty (e.g. `"1.5"` → `{1, ".5"}`) is rejected and returns the default. Returns `nil` (default) for non-numeric strings, floats, booleans, or anything else. Integer `0` is a valid ID and is preserved.

Integer input support is defensive for internal/test calls. Phoenix params are always strings at runtime.

A non-parseable `parent_agent_id` or `parent_session_id` silently becomes `nil`, which the validators treat as "not provided" — the DB check is skipped and no error is returned. This is intentional: bad type is treated as absent, not invalid.

---

## Validation Pipeline

`validate_params/1` runs validations in order. First failure short-circuits via `with`. `parse_int` runs at the top of the function before any validators.

All internal pipeline functions use a 3-tuple error shape `{:error, code, message}` so the `with` else clause can match uniformly. `AgentManager.create_agent/1` returns a standard 2-tuple and is handled in a nested `case` inside the `with` body — it never reaches the `else` clause.

`validate_params/1` skeleton:

```elixir
defp validate_params(params) do
  parent_agent_id   = parse_int(params["parent_agent_id"], nil)
  parent_session_id = parse_int(params["parent_session_id"], nil)
  model = params["model"] || "haiku"

  with {:ok, _} <- validate_instructions(params["instructions"]),
       {:ok, _} <- validate_model(model),
       {:ok, _} <- validate_parent_agent(parent_agent_id),
       {:ok, _} <- validate_parent_session(parent_session_id) do
    {:ok, Map.merge(params, %{
      "model"             => model,
      "parent_agent_id"   => parent_agent_id,
      "parent_session_id" => parent_session_id
    })}
  end
end
```

`validate_instructions/1` is a compound check returning different codes:
- `{:error, "missing_required", "instructions is required"}` if nil or blank.
- `{:error, "instructions_too_long", "instructions exceeds 32000 character limit"}` if length > 32,000.
- `{:ok, instructions}` otherwise.

Validations (1–2 are internal to `validate_instructions/1`; 3–5 are separate `with` clauses):

1. `instructions` present and non-empty → `missing_required`
2. `instructions` length ≤ 32,000 chars → `instructions_too_long`
3. `model` is one of `haiku`, `sonnet`, `opus` → `invalid_model`
4. `parent_agent_id` exists in DB if non-nil → `parent_not_found`
5. `parent_session_id` exists in DB if non-nil → `parent_not_found`

`resolve_team/1` receives the full params map and extracts `params["team_name"]` internally. Nil and empty string both treated as absent — returns `{:ok, nil}`. Returns `{:ok, team}` when found, `{:error, "team_not_found", "team not found: <name>"}` when non-blank name resolves to nothing.

---

## Structured Error Response

All errors return:

```json
{
  "error_code": "parent_not_found",
  "message": "parent_session_id 999 does not exist"
}
```

**Routing distinction:**

- Codes `missing_required`, `instructions_too_long`, `invalid_model`, `team_not_found`, `parent_not_found` — returned via the `with` `else` clause, always HTTP **400**.
- Code `spawn_failed` — returned via the nested `case` branch on `AgentManager` failure, always HTTP **422**.

`spawn_failed` is 422 regardless of whether the underlying cause is transient or permanent — the endpoint makes no attempt to classify it. Callers should treat all `spawn_failed` responses as non-retryable without changing the request.

`team_not_found` returns 400, not 404 — the team is not the primary resource of this endpoint; an invalid reference is a client error.

Both `parent_agent_id` and `parent_session_id` failures use `"parent_not_found"`. The `message` field identifies which. Intentional tradeoff to keep the error code surface small.

Error code table:

| Code | HTTP | Path | Trigger |
|------|------|------|---------|
| `missing_required` | 400 | `else` | `instructions` absent or blank |
| `instructions_too_long` | 400 | `else` | exceeds 32,000 chars |
| `invalid_model` | 400 | `else` | not `haiku`, `sonnet`, or `opus` |
| `team_not_found` | 400 | `else` | `team_name` non-blank but not found |
| `parent_not_found` | 400 | `else` | `parent_agent_id` or `parent_session_id` not in DB |
| `spawn_failed` | 422 | `case` | `AgentManager.create_agent/1` returned `{:error, _}` |

No internal details (changesets, stack traces) leak out.

Unexpected DB errors (connection failures, `Ecto.QueryError`, etc.) inside validators propagate as exceptions. Phoenix's error handler catches them. This is intentional crash behavior — DB layer exceptions are not mapped to error codes.

---

## Parent ID Validation

`Agents.get_agent/1` returns `{:ok, agent}` on success and `{:error, :not_found}` when the record doesn't exist. `Sessions.get_session/1` follows the same shape.

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

If both parent fields are invalid, only the first failure is reported (short-circuit).

---

## Controller Structure

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

Private helpers:

- `validate_params/1` — normalizes integers, defaults model, runs validations; returns `{:ok, params}` or `{:error, code, message}`
- `resolve_team/1` — extracts `team_name` from params; returns `{:ok, nil}` for nil/blank, `{:ok, team}` when found, `{:error, "team_not_found", message}` otherwise
- `apply_team_context/3` — `apply_team_context(instructions, nil, _)` returns `instructions` unchanged; `apply_team_context(instructions, team, member_name)` returns `instructions <> "\n\n" <> build_team_context(team, member_name)`. Pure function.
- `build_spawn_opts/2` — assembles `AgentManager` keyword list from normalized params; no validation logic
- `build_response/4` — `(agent, session, team, member_name)`; returns base map plus team fields when team is non-nil
- `validate_parent_agent/1`, `validate_parent_session/1` — DB existence checks; match `{:error, :not_found}` explicitly

`maybe_join_team/4` is fire-and-forget. Its result is not checked. A join failure does not roll back the spawn. `maybe_join_team/4` must log failures at `Logger.warning` level, including `agent_id`, `team_id`, and the error reason. The success response always includes `team_id`/`team_name` when a team was resolved — it reflects intent, not confirmed membership.

`build_team_context/2` is unchanged.

---

## Response Shape

`build_response/4` signature: `(agent, session, team, member_name)`.

Success (`201 Created`):

```json
{
  "success": true,
  "message": "Agent spawned",
  "agent_id": "agent-uuid",
  "session_id": 42,
  "session_uuid": "session-uuid"
}
```

With team:

```json
{
  "success": true,
  "message": "Agent spawned",
  "agent_id": "agent-uuid",
  "session_id": 42,
  "session_uuid": "session-uuid",
  "team_id": 1,
  "team_name": "my-team",
  "member_name": "worker-1"
}
```

`session_id` is the integer DB PK; `session_uuid` is the string UUID. Both included so callers can use whichever suits their next API call. Keys are atoms in the Elixir map; Phoenix serializes them to strings in JSON output.

---

## Out of Scope

- UUID strategy change (drop `--session-id`, let Claude generate) — separate task; non-trivial risk to session handoff
- Idempotency key — not needed at current scale
- `description` as first-class param — no current caller need
- Duplicate spawn protection — callers are responsible for deduplication

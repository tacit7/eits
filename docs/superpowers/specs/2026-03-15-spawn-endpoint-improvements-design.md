# Spawn Endpoint Improvements — Design Spec

**Date:** 2026-03-15 (revised 2026-03-16)
**Endpoint:** `POST /api/v1/agents`
**File:** `lib/eye_in_the_sky_web_web/controllers/api/v1/agent_controller.ex`

> Refactor `POST /api/v1/agents` into a normalized validation-and-execution pipeline with structured client-facing error codes, referential validation for parent IDs, and a minimal controller action that orchestrates request validation, optional team resolution, spawn execution, and response rendering.

---

## Problem

The spawn endpoint has two issues:

1. **Contract:** No structured error codes; parent IDs unvalidated; generic failure message loses reason; callers are agents that need actionable error detail.
2. **Code quality:** `create/2` is a deeply nested `cond` block mixing validation, team resolution, and spawn logic. No separation of concerns.

---

## Approach

Extract a validation pipeline, add parent ID DB checks, and return structured errors with codes. The `create/2` action becomes a clean `with` pipeline.

---

## Parent ID Coercion

Parent ID fields (`parent_agent_id`, `parent_session_id`) can be absent, blank, non-integer, or valid. The endpoint distinguishes all four cases:

| Input | Result |
|-------|--------|
| absent / nil / `""` | treated as not provided; DB check skipped |
| non-integer string (`"abc"`, `"1.5"`) | `400 invalid_parameter` |
| valid integer string (`"42"`) or integer (`42`) | parsed and passed to DB check |

A private `coerce_parent_id/2` helper handles this:

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

Integer input is supported defensively for internal/test calls; Phoenix params are always strings at runtime.

---

## Validation Pipeline

`validate_params/1` runs validations in order. First failure short-circuits via `with`. Coercion runs before DB checks.

All internal pipeline functions use a 3-tuple error shape `{:error, code, message}` so the `with` else clause can match uniformly. `AgentManager.create_agent/1` returns a standard 2-tuple and is handled in a nested `case` inside the `with` body — it never reaches the `else` clause.

`validate_params/1` skeleton:

```elixir
defp validate_params(params) do
  model = params["model"] || "haiku"

  with {:ok, _}                 <- validate_instructions(params["instructions"]),
       {:ok, _}                 <- validate_model(model),
       {:ok, parent_agent_id}   <- coerce_parent_id(params["parent_agent_id"], "parent_agent_id"),
       {:ok, parent_session_id} <- coerce_parent_id(params["parent_session_id"], "parent_session_id"),
       {:ok, _}                 <- validate_parent_agent(parent_agent_id),
       {:ok, _}                 <- validate_parent_session(parent_session_id) do
    {:ok, Map.merge(params, %{
      "model"             => model,
      "parent_agent_id"   => parent_agent_id,
      "parent_session_id" => parent_session_id
    })}
  end
end
```

**Validation order is intentional.** Only the first failure is reported. The order determines precedence:

1. `instructions` present, non-blank, within length limit
2. `model` valid
3. `parent_agent_id` coerces to integer (type check)
4. `parent_session_id` coerces to integer (type check)
5. `parent_agent_id` exists in DB
6. `parent_session_id` exists in DB

`validate_instructions/1` is a compound check:
- `nil`, `""`, or strings where `String.trim(val) == ""` → `{:error, "missing_required", "instructions is required"}`
- `String.length(trimmed) > 32_000` (Unicode grapheme count) → `{:error, "instructions_too_long", "instructions exceeds 32000 character limit"}`
- Otherwise → `{:ok, trimmed}`

The trimmed value is returned so whitespace-padded input is accepted but normalized.

`validate_model/1` checks against the `@valid_models` module attribute (the existing `~w(haiku sonnet opus)` constant) — the model allowlist lives in one place.

`resolve_team/1` runs after `validate_params/1`. Extracts `params["team_name"]` internally. Nil and empty string treated as absent — returns `{:ok, nil}`. Returns `{:ok, team}` when found, `{:error, "team_not_found", "team not found: <name>"}` when non-blank name resolves to nothing.

---

## Structured Error Response

All errors return:

```json
{
  "error_code": "invalid_parameter",
  "message": "parent_agent_id must be an integer"
}
```

**Routing distinction:**

- Codes `missing_required`, `instructions_too_long`, `invalid_model`, `invalid_parameter`, `team_not_found`, `parent_not_found` — returned via the `with` `else` clause, always HTTP **400**.
- Code `spawn_failed` — returned via the nested `case` branch on `AgentManager` failure, always HTTP **422**.

`team_not_found` returns 400, not 404 — the team is not the primary resource of this endpoint; an invalid reference is a client error.

`parent_not_found` is shared for both parent fields. The `message` field identifies which. Intentional tradeoff to keep the error code surface small.

`spawn_failed` is 422. The endpoint does not classify failures into retryable vs. non-retryable — `AgentManager` does not expose that information. Retry policy is the caller's responsibility. Callers should not blindly retry without understanding the failure.

Error code table:

| Code | HTTP | Path | Trigger |
|------|------|------|---------|
| `missing_required` | 400 | `else` | `instructions` nil, blank, or whitespace-only |
| `instructions_too_long` | 400 | `else` | grapheme count > 32,000 |
| `invalid_model` | 400 | `else` | not in `@valid_models` |
| `invalid_parameter` | 400 | `else` | `parent_agent_id` or `parent_session_id` present but not parseable as integer |
| `team_not_found` | 400 | `else` | `team_name` non-blank but not found |
| `parent_not_found` | 400 | `else` | `parent_agent_id` or `parent_session_id` not in DB |
| `spawn_failed` | 422 | `case` | `AgentManager.create_agent/1` returned `{:error, _}` |

No internal details (changesets, stack traces) leak out.

Unexpected DB errors inside validators propagate as exceptions and are handled by Phoenix's error handler. Not mapped to error codes.

---

## Parent ID Validation

`Agents.get_agent/1` returns `{:ok, agent}` or `{:error, :not_found}`. `Sessions.get_session/1` follows the same shape.

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

- `coerce_parent_id/2` — converts raw param to integer or returns `invalid_parameter` error; nil/blank → `{:ok, nil}`
- `validate_params/1` — coerces IDs, defaults model, runs validations in order; returns `{:ok, params}` or `{:error, code, message}`
- `resolve_team/1` — extracts `team_name`; returns `{:ok, nil}` for absent/blank, `{:ok, team}` when found, error tuple otherwise
- `apply_team_context/3` — `apply_team_context(instructions, nil, _)` returns instructions unchanged; non-nil team appends `build_team_context/2` output. Pure function.
- `build_spawn_opts/2` — assembles `AgentManager` keyword list from normalized params; no validation logic
- `build_response/4` — `(agent, session, team, member_name)`; base map plus team fields when team is non-nil
- `validate_parent_agent/1`, `validate_parent_session/1` — DB existence checks; match `{:error, :not_found}` explicitly

`maybe_join_team/4` is fire-and-forget. Its result is not checked. A join failure does not roll back the spawn. `maybe_join_team/4` must log failures at `Logger.warning` level with `agent_id`, `team_id`, and error reason.

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

With team (`team_id`/`team_name` reflect intent — team membership is not guaranteed if `maybe_join_team/4` failed silently):

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

`session_id` is the integer DB PK; `session_uuid` is the string UUID. Both included so callers can use whichever suits their next API call.

---

## Out of Scope

- UUID strategy change (drop `--session-id`, let Claude generate) — separate task
- Idempotency key — not needed at current scale
- `description` as first-class param — no current caller need
- Duplicate spawn protection — caller's responsibility
- Telemetry counters (`spawn.validation_failed`, `spawn.create_failed`, etc.) — v2 concern

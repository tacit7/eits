# GitHub Webhook Integration — Design Spec

**Date:** 2026-05-10
**Status:** Approved (v2 — post design review)

## Overview

Receive GitHub webhook events in EITS, persist PR state, trigger user-configured agent/task actions, and broadcast live UI updates. Smee.io is used as a local dev tunnel; production points GitHub directly at the server.

---

## Architecture

```
GitHub → smee.io (dev only) → POST /api/v1/webhooks/github
                                        ↓
                           GithubWebhookController
                             - read cached raw body
                             - verify X-Hub-Signature-256 (constant-time)
                             - read X-GitHub-Event + X-GitHub-Delivery
                             - derive event_type (header + action field)
                             - insert github_webhook_deliveries row
                             - deduplicate on delivery_id
                             - broadcast {:github_webhook_received, delivery_id}
                             - return 202 Accepted
                                        ↓
                           WebhookDispatcher (GenServer)
                             - loads delivery by id
                             - routes to built-in handlers
                             - runs WebhookRulesExecutor
                             - marks delivery processed/failed
                                        ↓
              ┌─────────────────────────┼─────────────────────────┐
      PullRequestHandler          PushHandler            CheckRunHandler
        (built-ins)               (built-ins)            (built-ins)
                                        ↓
                              WebhookRulesExecutor
                                - load rules matching event_type, repo, branch
                                - evaluate guards (once_per_pr, ignore_drafts, etc.)
                                - dispatch actions via RuleActions (no shelling out)
                                - record executions in github_webhook_rule_executions
```

**Key constraints:**
- Controller returns 202 (async accepted), not 200 (sync completed)
- PubSub carries only a delivery ID pointer, not the payload — handlers load from DB
- Rule actions call internal Elixir context functions, never shell out to `eits` CLI
- PubSub is a notification channel, not a queue — durable delivery row is the source of truth

---

## Router

Uses the existing `:accepts_json` pipeline (unauthenticated; auth is HMAC per-controller).

```
POST /api/v1/webhooks/github → GithubWebhookController
```

---

## Modules

| Module | Responsibility |
|---|---|
| `EyeInTheSky.Github.Webhook` | HMAC-SHA256 verification, header parsing, event type normalization |
| `EyeInTheSky.Github.WebhookDelivery` | Ecto schema for `github_webhook_deliveries` |
| `EyeInTheSky.Github.WebhookDeliveries` | Context: insert, deduplicate, update delivery status |
| `EyeInTheSkyWeb.Api.V1.GithubWebhookController` | Thin HTTP layer: validate, persist, broadcast, ack |
| `EyeInTheSky.Github.WebhookDispatcher` | GenServer: receives delivery IDs, routes to handlers |
| `EyeInTheSky.Github.PullRequestHandler` | Built-in PR state sync |
| `EyeInTheSky.Github.PushHandler` | Push-specific built-ins |
| `EyeInTheSky.Github.CheckRunHandler` | Check-run-specific built-ins |
| `EyeInTheSky.Github.WebhookRulesExecutor` | Loads rules, evaluates guards, dispatches actions |
| `EyeInTheSky.Github.RuleActions` | Internal action dispatch (spawn_agent, create_task, dm_session) |

---

## Database

### `github_webhook_deliveries`

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `delivery_id` | string | unique — from `X-GitHub-Delivery` header |
| `event_type` | string | normalized dotted form: `pull_request.opened`, `push`, etc. |
| `event_header` | string | raw `X-GitHub-Event` value |
| `action` | string | nullable — `action` field from payload body |
| `repository_full_name` | string | nullable |
| `sender_login` | string | nullable |
| `payload` | jsonb | parsed payload |
| `status` | string | `pending`, `processed`, `failed` |
| `error_message` | string | nullable |
| `received_at` | naive_datetime | |
| `processed_at` | naive_datetime | nullable |
| `inserted_at` | naive_datetime | |
| `updated_at` | naive_datetime | |

**Deduplication:** unique constraint on `delivery_id`. On conflict, return 202 and skip processing.

### `github_webhook_rules`

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `event_type` | string | dotted `<header>.<action>`, e.g. `pull_request.opened`; `push`; `*` matches all |
| `repository_full_name` | string | nullable — scopes to specific repo |
| `project_id` | bigint | nullable — FK to projects |
| `branch_glob` | string | nullable — matches head branch |
| `target_branch_glob` | string | nullable — matches base branch |
| `action_type` | string | `spawn_agent`, `create_task`, `dm_session`, `broadcast_only` |
| `action_config` | jsonb | action-specific params |
| `guard_config` | jsonb | `once_per_pr`, `ignore_drafts`, `only_if_label`, `max_runs_per_pr` |
| `enabled` | boolean | default true |
| `priority` | integer | default 100 — lower runs first |
| `inserted_at` | naive_datetime | |
| `updated_at` | naive_datetime | |

### `github_webhook_rule_executions`

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `rule_id` | bigint | FK |
| `delivery_id` | string | from delivery record |
| `repository_full_name` | string | |
| `pr_number` | integer | nullable |
| `status` | string | `ok`, `failed`, `skipped` |
| `result` | jsonb | nullable |
| `error_message` | string | nullable |
| `inserted_at` | naive_datetime | |

### `pull_requests` (existing — additions needed)

Add if not present:

| column | type | notes |
|---|---|---|
| `github_pr_id` | bigint | stable GitHub numeric PR ID — upsert key |
| `repository_full_name` | string | required — scopes PR number |
| `repository_id` | bigint | GitHub repo ID |
| `title` | string | |
| `state` | string | `open`, `closed` |
| `draft` | boolean | |
| `merged` | boolean | |
| `author_login` | string | |
| `last_synced_at` | naive_datetime | |

**Upsert key:** `github_pr_id` (globally unique) or `{repository_full_name, pr_number}` composite.
`pr_number` alone is not sufficient — it is only unique within a single repository.

---

## Data Flow

**Per request:**

1. Read raw body via body cache plug before JSON parsing (required for HMAC — Phoenix parses and discards raw bytes by default)
2. Verify `X-Hub-Signature-256`: must start with `sha256=`, compare with `Plug.Crypto.secure_compare/2`
3. Read `X-GitHub-Event` and `X-GitHub-Delivery` headers
4. Parse JSON body; derive `event_type` = `"#{event_header}.#{payload["action"]}"` when action present, else `event_header`
5. Insert `github_webhook_deliveries` row — on unique conflict with `delivery_id`, return 202 and skip
6. Broadcast `{:github_webhook_received, delivery_id}` on `"github:webhook_received"` PubSub topic
7. Return `202 Accepted`

**Per dispatcher (async, after 202):**

8. Load delivery by `delivery_id`
9. Run built-in handlers (PR upsert, UI broadcast)
10. Run `WebhookRulesExecutor`: load enabled matching rules, evaluate guards, dispatch actions via `RuleActions`
11. Record each rule execution in `github_webhook_rule_executions`
12. Mark delivery `processed` (or `failed` with error message)

**Raw body cache:** A plug must stash raw bytes before `Plug.Parsers` runs. Scope to the webhook route or the `:accepts_json` pipeline only.

---

## HMAC Verification

```elixir
# pseudo-code
defp verify(conn, secret) do
  sig_header = get_req_header(conn, "x-hub-signature-256") |> List.first()
  raw_body   = conn.assigns[:raw_body]  # from cache plug

  with "sha256=" <> hex <- sig_header,
       expected  <- :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower),
       true      <- Plug.Crypto.secure_compare(hex, expected) do
    :ok
  else
    _ -> :error
  end
end
```

- Missing signature → 401
- Malformed signature (no `sha256=` prefix) → 401
- Mismatch → 401, log warning
- Never log the signature value itself

---

## Rule Actions (Internal Only)

`RuleActions` calls internal context functions — no `System.cmd/3` or shelling out:

| `action_type` | Internal call |
|---|---|
| `spawn_agent` | `EyeInTheSky.Agents.spawn_agent(config)` |
| `create_task` | `EyeInTheSky.Tasks.begin_task(config)` |
| `dm_session` | `EyeInTheSky.Messages.send_dm(config)` |
| `broadcast_only` | `Phoenix.PubSub.broadcast(...)` |

`action_config` JSONB shape per type:
- `spawn_agent`: `{"agent": "codex-reviewer", "instructions": "Review PR {{pr_number}} in {{repository}}"}`
- `create_task`: `{"title": "Review: {{pr_title}}"}`
- `dm_session`: `{"session_id": 123, "message": "PR {{pr_number}} opened in {{repository}}"}`

Templates support `{{variable}}` interpolation from the delivery payload.

---

## Rule Guards

Evaluated before firing an action:

| guard | behavior |
|---|---|
| `once_per_pr: true` | Skip if `github_webhook_rule_executions` has a non-failed row for this rule + PR |
| `max_runs_per_pr: N` | Skip if execution count for this rule + PR >= N |
| `ignore_drafts: true` | Skip if payload `pull_request.draft == true` |
| `only_if_label: "name"` | Skip if PR labels do not include the named label |

---

## Error Handling

| Scenario | Behavior |
|---|---|
| HMAC mismatch | 401, log warning, drop |
| Missing/unknown event type | 202, log and drop — GitHub does not retry on 2xx |
| Duplicate `X-GitHub-Delivery` | 202, skip processing |
| DB insert failure | 500, let GitHub retry |
| Built-in handler error | Log error, mark delivery `failed`, do not crash dispatcher |
| Rule action failure | Log error, record `failed` execution, continue remaining rules |
| Dispatcher GenServer crash | Supervisor restarts; delivery row stays `pending` — can be reprocessed |

---

## Configuration

```
GITHUB_WEBHOOK_SECRET=<secret>
```

Read at runtime via `config/runtime.exs`. Must match the secret set in the GitHub repo webhook settings.

---

## Smee Dev Setup

Run alongside the Phoenix server:

```bash
npx smee-client \
  --url https://smee.io/<your-channel> \
  --target http://localhost:5001/api/v1/webhooks/github
```

Point the GitHub repo webhook at your smee.io URL. Document in `docs/SETUP.md`. Not wired into the app — manual step only.

---

## Settings UI

A section in settings for managing webhook rules:

- List rules with event type, repo filter, action type, enabled toggle, last execution status
- Create/edit rule: event type picker, optional repo/branch filters, action type + config, guard config
- Per-rule execution history (from `github_webhook_rule_executions`)

---

## Testing

**Unit — `EyeInTheSky.Github.WebhookTest`**
- Valid HMAC passes
- Tampered body fails
- Missing `X-Hub-Signature-256` header returns error
- Missing `sha256=` prefix returns error
- Constant-time compare handles different-length inputs safely
- Known event types with action normalize to dotted form
- Push (no action field) returns header only

**Delivery persistence — `WebhookDeliveriesTest`**
- New `X-GitHub-Delivery` inserts delivery
- Duplicate `X-GitHub-Delivery` returns conflict, does not double-process
- Missing delivery header: 202 and log (do not block delivery)

**Controller — `GithubWebhookControllerTest`**
- Valid payload + correct signature → 202 + PubSub broadcast fires
- Bad signature → 401
- Missing event header → 202, drop gracefully
- Returns 202, not 200

**Handler integration**
- `PullRequestHandler`: `opened` → row inserted with `github_pr_id` + `repository_full_name`; `closed` + merged → status updated; same PR number in different repos does not collide
- `PullRequestHandler`: draft PR with `ignore_drafts` rule guard → execution skipped
- `PullRequestHandler`: `synchronize` event updates existing PR without creating duplicate

**Rules**
- `once_per_pr` guard prevents duplicate agent spawn on re-open
- `branch_glob` filter matches head branch; non-matching skips rule
- `target_branch_glob` filter matches base branch
- Failed rule action records `failed` execution and continues remaining rules
- Rule with `broadcast_only` does not call agent/task/DM contexts

**Out of scope:** no end-to-end smee test — smee is a dev tunnel, not production infrastructure.

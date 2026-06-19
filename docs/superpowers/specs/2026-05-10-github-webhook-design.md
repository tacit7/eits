# GitHub Webhook Integration — Design Spec

**Date:** 2026-05-10
**Status:** Approved (v4 — post third design review)

## Overview

Receive GitHub webhook events in EITS, persist PR state, trigger user-configured agent/task actions, and broadcast live UI updates. Smee.io is used as a local dev tunnel; production points GitHub directly at the server.

---

## Architecture

```
GitHub → smee.io (dev only) → POST /api/v1/webhooks/github
                                        ↓
                           GithubWebhookController
                             - read cached raw body (route-scoped plug)
                             - verify X-Hub-Signature-256 (normalize hex, validate chars)
                             - 400 on missing event/delivery headers
                             - derive event_type (header + action field)
                             - insert github_webhook_deliveries row
                             - deduplicate on delivery_id (202 + increment duplicate_count)
                             - broadcast {:github_webhook_received, delivery_id}
                             - return 202 Accepted
                                        ↓
                           WebhookDispatcher (GenServer)
                             - on init: loads pending deliveries, re-enqueues oldest-first
                             - periodic recovery: re-enqueues stale processing rows
                             - atomic claim: UPDATE WHERE status='pending' RETURNING *
                             - routes to built-in handlers
                             - runs WebhookRulesExecutor
                             - marks delivery processed/failed
                             - respects max_attempts, does not retry beyond limit
                                        ↓
              ┌─────────────────────────┼─────────────────────────┐
      PullRequestHandler          PushHandler            CheckRunHandler
        (built-ins)               (built-ins)            (built-ins)
                   \                   |                  /
                    └──── EventContext normalizer ────────┘
                                        ↓
                              WebhookRulesExecutor
                                - load rules matching event_type, repo, branch
                                - evaluate guards
                                - RuleActions.dispatch(rule, ctx)
                                - record executions in github_webhook_rule_executions
```

**Key constraints:**
- Controller returns 202 (async accepted), not 200
- PubSub carries only a delivery ID pointer — handlers load from DB
- Claim is atomic: `UPDATE ... WHERE status = 'pending' RETURNING *`; no row = skip
- Rule actions call internal Elixir context functions, never shell out to `eits` CLI
- PubSub is a wake-up signal, not a queue — durable delivery row is the source of truth
- Raw body cache plug is route-scoped to the webhook endpoint only
- No long transactions; short transactions only for DB state transitions

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
| `EyeInTheSky.Github.EventContext` | Normalized struct extracted from raw payload |
| `EyeInTheSky.Github.Template` | `{{variable}}` interpolation against allowlisted context map |
| `EyeInTheSky.Github.WebhookDelivery` | Ecto schema for `github_webhook_deliveries` |
| `EyeInTheSky.Github.WebhookDeliveries` | Context: insert, deduplicate, atomic claim, update status |
| `EyeInTheSkyWeb.Api.V1.GithubWebhookController` | Thin HTTP layer: validate, persist, broadcast, ack |
| `EyeInTheSky.Github.WebhookDispatcher` | GenServer: receives delivery IDs, recovery on init, routes to handlers |
| `EyeInTheSky.Github.PullRequestHandler` | Built-in PR state sync |
| `EyeInTheSky.Github.PushHandler` | Push-specific built-ins |
| `EyeInTheSky.Github.CheckRunHandler` | Check-run-specific built-ins |
| `EyeInTheSky.Github.WebhookRulesExecutor` | Loads rules, evaluates guards, dispatches actions |
| `EyeInTheSky.Github.RuleActions` | `dispatch(rule, ctx)` — renders config, calls domain context |

---

## Database

### `github_webhook_deliveries`

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `delivery_id` | string | unique — from `X-GitHub-Delivery` header |
| `hook_id` | string | nullable — from `X-GitHub-Hook-ID` header |
| `event_type` | string | normalized dotted form: `pull_request.opened`, `push`, etc. |
| `event_header` | string | raw `X-GitHub-Event` value |
| `action` | string | nullable — `action` field from payload body |
| `repository_full_name` | string | nullable |
| `sender_login` | string | nullable |
| `pr_number` | integer | nullable — extracted for querying |
| `head_branch` | string | nullable — extracted for querying |
| `base_branch` | string | nullable — extracted for querying |
| `payload` | jsonb | parsed payload; pruned after 90 days |
| `status` | string | `pending`, `processing`, `processed`, `failed` |
| `error_message` | string | nullable |
| `processing_started_at` | naive_datetime | nullable |
| `processed_at` | naive_datetime | nullable |
| `attempt_count` | integer | default 0 |
| `max_attempts` | integer | default 5 |
| `duplicate_count` | integer | default 0 |
| `last_duplicate_at` | naive_datetime | nullable |
| `received_at` | naive_datetime | |
| `inserted_at` | naive_datetime | |
| `updated_at` | naive_datetime | |

**Deduplication:** unique constraint on `delivery_id`. On conflict: increment `duplicate_count`, update `last_duplicate_at`, return 202, skip processing.

**Status transitions:**
```
pending -> processing -> processed
pending -> processing -> failed
processing -> pending  (stale timeout recovery, only if attempt_count < max_attempts)
processing -> failed   (if attempt_count >= max_attempts)
```

**Payload retention:** after 90 days, set `payload = null` on `processed` and `failed` rows. Keep `delivery_id`, `event_type`, `repository_full_name`, `status`, `error_message`, and timestamps.

### Indexes for `github_webhook_deliveries`

```sql
CREATE UNIQUE INDEX github_webhook_deliveries_delivery_id_index
  ON github_webhook_deliveries (delivery_id);

CREATE INDEX github_webhook_deliveries_status_received_at_index
  ON github_webhook_deliveries (status, received_at);

CREATE INDEX github_webhook_deliveries_stale_processing_index
  ON github_webhook_deliveries (processing_started_at)
  WHERE status = 'processing';
```

### `github_webhook_rules`

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `event_type` | string | dotted `<header>.<action>`, e.g. `pull_request.opened`; `push`; `*` matches all |
| `repository_full_name` | string | nullable — scopes to specific repo |
| `project_id` | bigint | nullable — FK to projects |
| `branch_glob` | string | nullable — matches head branch (via EventContext) |
| `target_branch_glob` | string | nullable — matches base branch |
| `action_type` | string | `spawn_agent`, `create_task`, `dm_session`, `broadcast_only` |
| `action_config` | jsonb | validated at save time per action_type |
| `guard_config` | jsonb | validated at save time |
| `enabled` | boolean | default true |
| `priority` | integer | default 100 — lower runs first |
| `inserted_at` | naive_datetime | |
| `updated_at` | naive_datetime | |

### Index for `github_webhook_rules`

```sql
CREATE INDEX github_webhook_rules_enabled_event_repo_index
  ON github_webhook_rules (enabled, event_type, repository_full_name);
```

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

### Index for `github_webhook_rule_executions`

```sql
CREATE INDEX github_webhook_rule_executions_rule_repo_pr_status_index
  ON github_webhook_rule_executions (rule_id, repository_full_name, pr_number, status);
```

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

**Upsert key:** `github_pr_id`. `pr_number` alone is not sufficient.

```sql
-- partial index during migration (github_pr_id may be null on existing rows)
CREATE UNIQUE INDEX pull_requests_github_pr_id_index
  ON pull_requests (github_pr_id)
  WHERE github_pr_id IS NOT NULL;
```

---

## Data Flow

**Per request:**

1. Route-scoped raw body cache plug stashes bytes before `Plug.Parsers` runs
2. Verify `X-Hub-Signature-256` — return 401 on missing, malformed, non-hex, or mismatch
3. Read `X-GitHub-Event` — return 400 if missing
4. Read `X-GitHub-Delivery` — return 400 if missing
5. Read `X-GitHub-Hook-ID` (optional, nullable)
6. Parse JSON body; derive `event_type` = `"#{event_header}.#{payload["action"]}"` when action present, else `event_header`
7. Insert `github_webhook_deliveries` row — on `delivery_id` conflict: update duplicate counters, return 202, stop
8. Broadcast `{:github_webhook_received, delivery_id}` on `"github:webhook_received"` PubSub topic
9. Return `202 Accepted`

**Per dispatcher (async):**

10. Atomic claim: `UPDATE ... SET status='processing', attempt_count=attempt_count+1, processing_started_at=now() WHERE delivery_id=$1 AND status='pending' RETURNING *` — if no row, skip (duplicate wake-up)
11. Build `EventContext` from delivery payload
12. Run built-in handlers (short transactions: upsert PR record, broadcast UI)
13. Run `WebhookRulesExecutor`: load enabled matching rules, evaluate guards, call `RuleActions.dispatch(rule, ctx)` per rule
14. Record each rule execution in `github_webhook_rule_executions` (short transaction)
15. Mark delivery `processed` with `processed_at`, or `failed` with `error_message` (short transaction)

**Transaction rule:** never hold a DB transaction while spawning agents, creating tasks, or sending DMs. Short transactions only for each discrete state transition.

---

## Dispatcher Recovery

**On init:**
- Query `status = 'pending'` ordered by `received_at ASC`
- Enqueue each `delivery_id`

**Periodic recovery (every 60s):**
- Re-enqueue `status = 'pending'`
- Find `status = 'processing'` and `processing_started_at < now() - 5 minutes`:
  - If `attempt_count < max_attempts`: reset to `pending`, re-enqueue
  - Else: mark `failed` with `error_message = "max attempts exceeded"`

PubSub is a wake-up signal. The DB is the durable inbox.

---

## EventContext

Normalized struct — handlers and rules use this, not raw payload:

```elixir
%EyeInTheSky.Github.EventContext{
  delivery_id:           "abc-123",
  event_type:            "pull_request.opened",
  repository_full_name:  "tacit7/eits",
  sender_login:          "urielmaldonado",
  github_pr_id:          456,
  pr_number:             42,
  head_branch:           "feature/foo",
  base_branch:           "main",
  labels:                ["agent-review"],
  draft?:                false,
  merged?:               false
}
```

Branch extraction is event-specific inside `EventContext`:
- PR events: `head_branch` from `pull_request.head.ref`, `base_branch` from `pull_request.base.ref`
- Push events: `head_branch` from `ref` stripped of `refs/heads/`; `base_branch` not applicable
- Check run events: `head_branch` from `check_run.check_suite.head_branch`

---

## HMAC Verification

```elixir
defp verify(conn, secret) do
  sig_header = get_req_header(conn, "x-hub-signature-256") |> List.first()
  raw_body   = conn.assigns[:raw_body]

  with "sha256=" <> hex <- sig_header,
       hex      <- String.downcase(hex),
       true     <- Regex.match?(~r/\A[0-9a-f]{64}\z/, hex),
       expected <- :crypto.mac(:hmac, :sha256, secret, raw_body)
                   |> Base.encode16(case: :lower),
       true     <- secure_equal?(hex, expected) do
    :ok
  else
    _ -> :error
  end
end

defp secure_equal?(left, right) when byte_size(left) == byte_size(right) do
  Plug.Crypto.secure_compare(left, right)
end
defp secure_equal?(_, _), do: false
```

- Missing or malformed signature → 401
- Hex not matching `[0-9a-f]{64}` → 401
- Mismatch → 401, log warning (never log the signature value)

---

## HTTP Response Matrix

| Scenario | Response |
|---|---|
| Bad or missing HMAC | 401 |
| Missing `X-GitHub-Event` header | 400 |
| Missing `X-GitHub-Delivery` header | 400 |
| Duplicate `delivery_id` | 202, update duplicate counters, skip |
| Unknown event type | 202, persist with `status=processed`, drop |
| DB insert failure | 500, let GitHub retry |
| Valid delivery accepted | 202 |

---

## Rule Actions

`RuleActions.dispatch(rule, ctx)` renders the config template against `EventContext`, then calls the appropriate domain function:

| `action_type` | Internal call |
|---|---|
| `spawn_agent` | `EyeInTheSky.Agents.spawn_agent(rendered_config)` |
| `create_task` | `EyeInTheSky.Tasks.begin_task(rendered_config)` |
| `dm_session` | `EyeInTheSky.Messages.send_dm(rendered_config)` |
| `broadcast_only` | `Phoenix.PubSub.broadcast(...)` |

**Template allowlist** — only these variables are available in `{{variable}}` interpolation:

```elixir
%{
  "repository"   => ctx.repository_full_name,
  "event_type"   => ctx.event_type,
  "sender_login" => ctx.sender_login,
  "pr_number"    => ctx.pr_number,
  "pr_title"     => pr.title,
  "pr_url"       => pr.html_url,
  "head_branch"  => ctx.head_branch,
  "base_branch"  => ctx.base_branch
}
```

Unknown variables fail validation at rule-save time, not at dispatch time.

**`action_config` validation at save time:**

| `action_type` | Required keys |
|---|---|
| `spawn_agent` | `agent`, `instructions` |
| `create_task` | `title` |
| `dm_session` | `session_id`, `message` |
| `broadcast_only` | `topic`, `message` |

**`guard_config` validation at save time:**

| key | type | notes |
|---|---|---|
| `once_per_pr` | boolean | |
| `max_runs_per_pr` | integer | > 0 |
| `ignore_drafts` | boolean | |
| `only_if_label` | string | |

---

## Rule Guards

Evaluated via `EventContext` before firing:

| guard | behavior |
|---|---|
| `once_per_pr: true` | Skip if `github_webhook_rule_executions` has `status = "ok"` for this rule + repo + pr_number. `skipped` prior execution does NOT block — a draft that becomes ready should still fire. |
| `max_runs_per_pr: N` | Skip if `status = "ok"` count for this rule + repo + pr_number >= N |
| `ignore_drafts: true` | Skip if `EventContext.draft? == true` |
| `only_if_label: "name"` | Skip if `EventContext.labels` does not include the named label |

---

## Error Handling

| Scenario | Behavior |
|---|---|
| HMAC mismatch | 401, log warning, drop |
| Missing required headers | 400 |
| Duplicate `X-GitHub-Delivery` | 202, update duplicate counters, skip |
| DB insert failure | 500, let GitHub retry |
| Built-in handler error | Log error, mark delivery `failed` |
| Rule action failure | Log error, record `failed` execution, continue remaining rules |
| Dispatcher crash | Supervisor restarts; pending/stale processing rows re-enqueued on init |
| Max attempts exceeded | Mark delivery `failed`, do not re-enqueue |

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

Point the GitHub repo webhook at your smee.io URL. Document in `docs/SETUP.md`. Not wired into the app.

---

## Settings UI

- List rules: event type, repo filter, action type, enabled toggle, last execution status
- Create/edit rule: event type picker, optional repo/branch filters, action type + config fields, guard config, template variable reference panel
- Template validation at save time — unknown `{{variable}}` names rejected
- Per-rule execution history (from `github_webhook_rule_executions`)
- Manual retry button for `failed` deliveries that hit `max_attempts`

---

## Testing

**Unit — `EyeInTheSky.Github.WebhookTest`**
- Valid HMAC passes
- Tampered body fails
- Missing header returns error
- Missing `sha256=` prefix returns error
- Uppercase hex is normalized before compare
- Non-hex characters in signature return error
- Hex length != 64 returns error
- `secure_equal?/2` returns false for different-length inputs without calling `secure_compare`
- Known event types with action normalize to dotted form
- Push (no action field) returns header only

**Delivery persistence — `WebhookDeliveriesTest`**
- New `X-GitHub-Delivery` inserts with `status=pending`, `attempt_count=0`
- Duplicate `X-GitHub-Delivery` increments `duplicate_count`, does not process twice
- Atomic claim returns row when `status=pending`; returns nothing if already `processing`
- Recovery query returns `pending` and stale `processing` rows
- Recovery marks `failed` when `attempt_count >= max_attempts`

**Controller — `GithubWebhookControllerTest`**
- Valid payload + correct signature → 202 + PubSub broadcast fires
- Bad signature → 401
- Missing `X-GitHub-Event` header → 400
- Missing `X-GitHub-Delivery` header → 400
- Returns 202, not 200

**Dispatcher recovery**
- On init with pending deliveries: all are enqueued and processed
- Stale `processing` row (beyond timeout) with attempts remaining → reset to `pending`, re-enqueued
- Stale `processing` row at `max_attempts` → marked `failed`, not re-enqueued
- Duplicate PubSub fire for same delivery does not double-process (atomic claim returns no row)

**Handler integration**
- `PullRequestHandler`: `opened` → row inserted with `github_pr_id` + `repository_full_name`
- `PullRequestHandler`: `closed` + merged → status updated
- Same PR number in different repos does not collide
- `synchronize` updates existing PR without creating duplicate

**EventContext**
- PR event extracts `head_branch` from `pull_request.head.ref`
- Push event strips `refs/heads/` from `ref`
- Check run event reads `check_run.check_suite.head_branch`

**Rules**
- `once_per_pr` skips on `status="ok"` prior execution; does NOT skip on `status="skipped"`
- `ignore_drafts` skips when `EventContext.draft? == true`
- `branch_glob` matches head branch; non-matching skips
- `target_branch_glob` matches base branch
- Failed action records `failed` execution, continues remaining rules
- `broadcast_only` does not call agent/task/DM contexts
- Unknown template variable fails at rule-save validation
- Missing required `action_config` key fails at rule-save validation

**Out of scope:** no end-to-end smee test.

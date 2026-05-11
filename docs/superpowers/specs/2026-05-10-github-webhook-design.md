# GitHub Webhook Integration — Design Spec

**Date:** 2026-05-10
**Status:** Approved (v3 — post second design review)

## Overview

Receive GitHub webhook events in EITS, persist PR state, trigger user-configured agent/task actions, and broadcast live UI updates. Smee.io is used as a local dev tunnel; production points GitHub directly at the server.

---

## Architecture

```
GitHub → smee.io (dev only) → POST /api/v1/webhooks/github
                                        ↓
                           GithubWebhookController
                             - read cached raw body (route-scoped plug)
                             - verify X-Hub-Signature-256 (constant-time)
                             - 400 on missing event/delivery headers
                             - derive event_type (header + action field)
                             - insert github_webhook_deliveries row
                             - deduplicate on delivery_id (202 on conflict)
                             - broadcast {:github_webhook_received, delivery_id}
                             - return 202 Accepted
                                        ↓
                           WebhookDispatcher (GenServer)
                             - on init: loads pending deliveries, re-enqueues oldest-first
                             - periodic recovery: re-enqueues stale processing rows
                             - atomically transitions pending -> processing
                             - routes to built-in handlers
                             - runs WebhookRulesExecutor
                             - marks delivery processed/failed
                                        ↓
              ┌─────────────────────────┼─────────────────────────┐
      PullRequestHandler          PushHandler            CheckRunHandler
        (built-ins)               (built-ins)            (built-ins)
                   \                   |                  /
                    └──── EventContext normalizer ────────┘
                                        ↓
                              WebhookRulesExecutor
                                - load rules matching event_type, repo, branch
                                - evaluate guards (once_per_pr uses status="ok" only)
                                - dispatch actions via RuleActions (no shelling out)
                                - record executions in github_webhook_rule_executions
```

**Key constraints:**
- Controller returns 202 (async accepted), not 200
- PubSub carries only a delivery ID pointer — handlers load from DB
- Rule actions call internal Elixir context functions, never shell out to `eits` CLI
- PubSub is a wake-up signal, not a queue — durable delivery row is the source of truth
- Raw body cache plug is route-scoped to the webhook endpoint only

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
| `EyeInTheSky.Github.EventContext` | Normalized struct extracted from raw payload (branch, PR info, labels, etc.) |
| `EyeInTheSky.Github.WebhookDelivery` | Ecto schema for `github_webhook_deliveries` |
| `EyeInTheSky.Github.WebhookDeliveries` | Context: insert, deduplicate, update delivery status |
| `EyeInTheSkyWeb.Api.V1.GithubWebhookController` | Thin HTTP layer: validate, persist, broadcast, ack |
| `EyeInTheSky.Github.WebhookDispatcher` | GenServer: receives delivery IDs, recovery on init, routes to handlers |
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
| `pr_number` | integer | nullable — extracted for querying |
| `head_branch` | string | nullable — extracted for querying |
| `base_branch` | string | nullable — extracted for querying |
| `payload` | jsonb | parsed payload |
| `status` | string | `pending`, `processing`, `processed`, `failed` |
| `error_message` | string | nullable |
| `processing_started_at` | naive_datetime | nullable |
| `attempt_count` | integer | default 0 |
| `duplicate_count` | integer | default 0 |
| `last_duplicate_at` | naive_datetime | nullable |
| `received_at` | naive_datetime | |
| `processed_at` | naive_datetime | nullable |
| `inserted_at` | naive_datetime | |
| `updated_at` | naive_datetime | |

**Deduplication:** unique constraint on `delivery_id`. On conflict: increment `duplicate_count`, update `last_duplicate_at`, return 202, skip processing.

**Status transitions:**
```
pending -> processing -> processed
pending -> processing -> failed
processing -> pending  (stale timeout recovery)
```

### `github_webhook_rules`

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `event_type` | string | dotted `<header>.<action>`, e.g. `pull_request.opened`; `push`; `*` matches all |
| `repository_full_name` | string | nullable — scopes to specific repo |
| `project_id` | bigint | nullable — FK to projects |
| `branch_glob` | string | nullable — matches head branch (event-specific via EventContext) |
| `target_branch_glob` | string | nullable — matches base branch |
| `action_type` | string | `spawn_agent`, `create_task`, `dm_session`, `broadcast_only` |
| `action_config` | jsonb | action-specific params with `{{variable}}` templates |
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

**Upsert key:** `github_pr_id` (globally unique). `pr_number` alone is not sufficient — only unique within a repository.

---

## Data Flow

**Per request:**

1. Route-scoped raw body cache plug stashes bytes before `Plug.Parsers` runs
2. Verify `X-Hub-Signature-256` — return 401 on missing, malformed, or mismatch
3. Read `X-GitHub-Event` — return 400 if missing
4. Read `X-GitHub-Delivery` — return 400 if missing
5. Parse JSON body; derive `event_type` = `"#{event_header}.#{payload["action"]}"` when action present, else `event_header`
6. Insert `github_webhook_deliveries` row — on `delivery_id` conflict: update duplicate counters, return 202, stop
7. Broadcast `{:github_webhook_received, delivery_id}` on `"github:webhook_received"` PubSub topic
8. Return `202 Accepted`

**Per dispatcher (async):**

9. Atomically transition delivery `pending -> processing`, increment `attempt_count`, set `processing_started_at`
10. Build `EventContext` from delivery payload
11. Run built-in handlers (PR upsert, UI broadcast)
12. Run `WebhookRulesExecutor`: load enabled matching rules, evaluate guards, dispatch actions via `RuleActions`
13. Record each rule execution in `github_webhook_rule_executions`
14. Mark delivery `processed` with `processed_at`, or `failed` with `error_message`

---

## Dispatcher Recovery

`WebhookDispatcher` must not rely solely on PubSub for delivery.

**On init:**
- Query `github_webhook_deliveries` where `status = 'pending'`
- Enqueue oldest-first

**Periodic recovery (every 60s):**
- Re-enqueue where `status = 'pending'`
- Re-enqueue where `status = 'processing'` and `processing_started_at < now() - 5 minutes` (stale)
- Reset stale `processing` rows back to `pending` before re-enqueueing

PubSub is a wake-up signal. The DB is the durable inbox. After a crash, the dispatcher re-reads the inbox on restart.

---

## EventContext

Normalized struct built from raw payload — handlers and rules use this, not raw JSON:

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

Rules engine and handlers consume `EventContext` only — no payload archaeology in business logic.

---

## HMAC Verification

```elixir
defp verify(conn, secret) do
  sig_header = get_req_header(conn, "x-hub-signature-256") |> List.first()
  raw_body   = conn.assigns[:raw_body]

  with "sha256=" <> hex <- sig_header,
       true <- byte_size(hex) == 64,
       expected <- :crypto.mac(:hmac, :sha256, secret, raw_body)
                   |> Base.encode16(case: :lower),
       true <- secure_equal?(hex, expected) do
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

- Missing signature → 401
- Missing `sha256=` prefix → 401
- Hex length != 64 → 401
- Mismatch → 401, log warning
- Never log the signature value itself

---

## HTTP Response Matrix

| Scenario | Response |
|---|---|
| Bad or missing HMAC | 401 |
| Missing `X-GitHub-Event` header | 400 |
| Missing `X-GitHub-Delivery` header | 400 |
| Duplicate `delivery_id` | 202, skip |
| Unknown event type | 202, persist with `status=processed`, drop |
| DB insert failure | 500, let GitHub retry |
| Valid delivery accepted | 202 |

---

## Rule Actions (Internal Only)

`RuleActions` calls internal context functions — no `System.cmd/3` or shelling out:

| `action_type` | Internal call |
|---|---|
| `spawn_agent` | `EyeInTheSky.Agents.spawn_agent(config)` |
| `create_task` | `EyeInTheSky.Tasks.begin_task(config)` |
| `dm_session` | `EyeInTheSky.Messages.send_dm(config)` |
| `broadcast_only` | `Phoenix.PubSub.broadcast(...)` |

**Template interpolation** uses an explicit allowlist — no arbitrary payload path access:

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

Unknown variables fail validation at rule-save time, not at runtime.

`action_config` JSONB examples:
- `spawn_agent`: `{"agent": "codex-reviewer", "instructions": "Review PR {{pr_number}} in {{repository}}"}`
- `create_task`: `{"title": "Review: {{pr_title}}"}`
- `dm_session`: `{"session_id": 123, "message": "PR {{pr_number}} opened in {{repository}}"}`

---

## Rule Guards

Evaluated before firing an action using `EventContext`:

| guard | behavior |
|---|---|
| `once_per_pr: true` | Skip if `github_webhook_rule_executions` has `status = "ok"` for this rule + repo + pr_number. A `skipped` prior execution does NOT block — e.g. a draft that later becomes ready should still fire. |
| `max_runs_per_pr: N` | Skip if `status = "ok"` execution count for this rule + repo + pr_number >= N |
| `ignore_drafts: true` | Skip if `EventContext.draft? == true` |
| `only_if_label: "name"` | Skip if `EventContext.labels` does not include the named label |

---

## Error Handling

| Scenario | Behavior |
|---|---|
| HMAC mismatch | 401, log warning, drop |
| Missing required headers | 400 |
| Duplicate `X-GitHub-Delivery` | 202, update duplicate counters, skip processing |
| DB insert failure | 500, let GitHub retry |
| Built-in handler error | Log error, mark delivery `failed`, do not crash dispatcher |
| Rule action failure | Log error, record `failed` execution, continue remaining rules |
| Dispatcher crash | Supervisor restarts; `pending`/stale `processing` rows re-enqueued on init |

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
- Create/edit rule: event type picker, optional repo/branch filters, action type + config, guard config, template variable reference
- Per-rule execution history (from `github_webhook_rule_executions`)
- Template validation at save time — unknown `{{variable}}` names are rejected

---

## Testing

**Unit — `EyeInTheSky.Github.WebhookTest`**
- Valid HMAC passes
- Tampered body fails
- Missing `X-Hub-Signature-256` returns error
- Missing `sha256=` prefix returns error
- Hex length != 64 returns error
- `secure_equal?/2` returns false for different-length inputs without calling `secure_compare`
- Known event types with action normalize to dotted form
- Push (no action field) returns header only

**Delivery persistence — `WebhookDeliveriesTest`**
- New `X-GitHub-Delivery` inserts delivery with `status=pending`
- Duplicate `X-GitHub-Delivery` increments `duplicate_count`, does not process twice
- Recovery query returns `pending` and stale `processing` rows

**Controller — `GithubWebhookControllerTest`**
- Valid payload + correct signature → 202 + PubSub broadcast fires
- Bad signature → 401
- Missing `X-GitHub-Event` header → 400
- Missing `X-GitHub-Delivery` header → 400
- Returns 202, not 200

**Dispatcher recovery**
- On init with pending deliveries: all are enqueued and processed
- Stale `processing` row (beyond timeout) is reset to `pending` and reprocessed
- Duplicate PubSub fire for same delivery_id does not double-process

**Handler integration**
- `PullRequestHandler`: `opened` → row inserted with `github_pr_id` + `repository_full_name`
- `PullRequestHandler`: `closed` + merged → status updated
- Same PR number in different repos does not collide
- `synchronize` event updates existing PR without creating duplicate

**EventContext**
- PR event extracts `head_branch` from `pull_request.head.ref`
- Push event strips `refs/heads/` from `ref`
- Check run event reads `check_run.check_suite.head_branch`

**Rules**
- `once_per_pr` skips on `status="ok"` prior execution; does NOT skip on `status="skipped"`
- `ignore_drafts` skips when `EventContext.draft? == true`
- `branch_glob` filter matches head branch; non-matching skips rule
- `target_branch_glob` filter matches base branch
- Failed rule action records `failed` execution and continues remaining rules
- `broadcast_only` does not call agent/task/DM contexts
- Template with unknown variable fails validation at save time

**Out of scope:** no end-to-end smee test.

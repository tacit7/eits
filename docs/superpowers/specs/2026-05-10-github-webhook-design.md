# GitHub Webhook Integration — Design Spec

**Date:** 2026-05-10
**Status:** Approved

## Overview

Receive GitHub webhook events in EITS, persist PR state, trigger user-configured agent/task actions, and broadcast live UI updates. Smee.io is used as a local dev tunnel; production points GitHub directly at the server.

---

## Architecture

```
GitHub → smee.io (dev only) → POST /api/v1/webhooks/github
                                        ↓
                           GithubWebhookController
                             - verify HMAC-SHA256
                             - read X-GitHub-Event header
                             - broadcast to PubSub
                             - return 200 immediately
                                        ↓
              ┌─────────────────────────┼─────────────────────────┐
      PullRequestHandler          PushHandler            CheckRunHandler
        (built-ins + rules)      (built-ins + rules)    (built-ins + rules)
                                        ↓
                              WebhookRulesExecutor
                                - load matching rules from DB
                                - fire configured actions
```

**Handler GenServers** start under the app supervision tree, subscribe to PubSub in `init/1`, and process events in `handle_info/2`.

**Built-in actions** (always run, not user-configurable):
- Upsert `pull_requests` record on PR events
- Broadcast UI update via `Phoenix.PubSub` on `"pull_requests:updated"` topic (same topic the DM page already subscribes to for PR panel live updates)

**Rule actions** (user-configured, additive):
- `spawn_agent` — run `eits agents spawn` with configured agent and instructions
- `create_task` — run `eits tasks begin` with a title template
- `dm_session` — run `eits dm --to <session>` with a message template
- `broadcast_only` — PubSub only, no side effects

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
| `EyeInTheSky.Github.Webhook` | HMAC-SHA256 verification, event type parsing |
| `EyeInTheSkyWeb.Api.V1.GithubWebhookController` | HTTP layer: validate, broadcast, ack |
| `EyeInTheSky.Github.PullRequestHandler` | GenServer; handles `pull_request.*` events |
| `EyeInTheSky.Github.PushHandler` | GenServer; handles `push` events |
| `EyeInTheSky.Github.CheckRunHandler` | GenServer; handles `check_run.*` events |
| `EyeInTheSky.Github.WebhookRulesExecutor` | Loads rules from DB, dispatches actions |

---

## Database

### `github_webhook_rules`

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `event_type` | string | dotted `<header>.<action>` e.g. `pull_request.opened`, `check_run.completed`; header-only for events with no action field e.g. `push`; `*` matches all |
| `action_type` | string | `spawn_agent`, `create_task`, `dm_session`, `broadcast_only` |
| `action_config` | jsonb | action-specific params (agent name, title template, DM target) |
| `enabled` | boolean | default true |
| `inserted_at` | naive_datetime | |
| `updated_at` | naive_datetime | |

### `pull_requests` (existing)

No schema changes needed. Built-in handler upserts on `pr_number` per event.

---

## Data Flow

**Per request:**

1. Read raw body before JSON parsing (required for HMAC)
2. Verify `X-Hub-Signature-256` header — return 401 on mismatch
3. Parse JSON body
4. Broadcast to `"github:<event_type>"` PubSub topic
5. Return 200 — GitHub expects fast ack; all processing is async

**Per handler (after 200):**

6. Built-ins run first: upsert DB, broadcast UI
7. `WebhookRulesExecutor` loads enabled rules matching `event_type`, fires each action

**Raw body gotcha:** Phoenix parses the body by default, consuming the bytes needed for HMAC verification. A raw body cache plug must be added to the `:accepts_json` pipeline (or scoped to this route) to stash the raw bytes before parsing.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| HMAC mismatch | 401, log warning, drop payload |
| Missing/unknown event type | 200, log and drop — no retry from GitHub |
| DB upsert failure | Log error, continue — stale record corrected by next event |
| Rule action failure | Log error per rule, continue remaining rules |
| Handler GenServer crash | Supervisor restarts it; events during gap are lost (acceptable — GitHub won't retry 200) |

---

## Configuration

```
GITHUB_WEBHOOK_SECRET=<secret>
```

Read at runtime via `config/runtime.exs`. Must match the secret configured in the GitHub repo webhook settings.

---

## Smee Dev Setup

Run alongside the Phoenix server:

```bash
npx smee-client \
  --url https://smee.io/<your-channel> \
  --target http://localhost:5001/api/v1/webhooks/github
```

Document in `docs/SETUP.md`. Not wired into the application — manual step only.

---

## Settings UI

A new section in the settings panel for configuring webhook rules:

- List existing rules (event type, action type, enabled toggle)
- Create rule: pick event type from dropdown, pick action type, fill `action_config` fields
- Enable/disable rules without deleting them

---

## Testing

**Unit — `EyeInTheSky.Github.WebhookTest`**
- Valid HMAC passes
- Tampered body fails
- Missing header returns error
- Known event types parse correctly
- Unknown event type returns `:unknown`

**Controller — `GithubWebhookControllerTest`**
- Valid payload + correct signature → 200 + PubSub broadcast fires
- Bad signature → 401
- Missing event header → 200, drop gracefully

**Handler integration**
- `PullRequestHandler`: `opened` → row inserted; `closed` + merged → status updated
- `WebhookRulesExecutor`: seed a rule, fire matching event, assert action was called (Mox agent spawn / DM)
- Ecto sandbox for DB isolation

**Out of scope:** no end-to-end smee test — smee is a dev tunnel, not production infrastructure.

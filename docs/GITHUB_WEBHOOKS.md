# GitHub Webhook Integration

Receives all GitHub events, persists a durable delivery inbox, syncs PR state, and fires user-configurable rules (spawn agent, create task, DM a session).

## Architecture

```
GitHub → POST /api/v1/webhooks/github
           │
           ├── HMAC verify (X-Hub-Signature-256)
           ├── Deduplication (X-GitHub-Delivery)
           ├── Insert github_webhook_deliveries (status: pending)
           ├── PubSub broadcast: github_webhook_received
           └── 202 immediately

WebhookDispatcher (GenServer)
           │
           ├── Subscribes to PubSub on init
           ├── Recovers pending rows on init
           ├── Every 60s: recovers stale processing rows (stuck > 5min)
           │
           └── On event: atomic claim → EventContext → built-ins + rules
```

## Key Modules

| Module | Location | Responsibility |
|--------|----------|----------------|
| `GithubWebhookController` | `controllers/api/v1/github_webhook_controller.ex` | HTTP ingestion, HMAC gate, insert + broadcast |
| `Webhook` | `github/webhook.ex` | HMAC verify, event type normalization |
| `RawBodyCache` | `plugs/raw_body_cache.ex` | Cache raw body for HMAC (scoped to webhook route) |
| `WebhookDeliveries` | `github/webhook_deliveries.ex` | Insert, claim, mark_processed/failed, pending, stale_processing |
| `WebhookDispatcher` | `github/webhook_dispatcher.ex` | GenServer: PubSub listener, atomic claim, recovery |
| `EventContext` | `github/event_context.ex` | Normalized struct from delivery payload |
| `PullRequestHandler` | `github/pull_request_handler.ex` | Upsert pull_requests row keyed on github_pr_id |
| `PushHandler` | `github/push_handler.ex` | Handle push events |
| `CheckRunHandler` | `github/check_run_handler.ex` | Handle check_run events |
| `WebhookRules` | `github/webhook_rules.ex` | CRUD for webhook_rules table |
| `WebhookRulesExecutor` | `github/webhook_rules_executor.ex` | Guard evaluation, rule matching |
| `RuleActions` | `github/rule_actions.ex` | Action dispatch: spawn_agent, create_task, dm_session |
| `Template` | `github/template.ex` | `{{variable}}` interpolation with allowlist |

## Delivery State Machine

```
pending → processing → processed
                    ↘ failed
```

- `pending`: inserted by controller, not yet claimed
- `processing`: atomically claimed by dispatcher (`UPDATE WHERE status='pending' RETURNING *`)
- `processed`: built-ins + rules ran successfully
- `failed`: exception during processing, or `attempt_count >= max_attempts`

Stale recovery: any row stuck in `processing` for > 5 minutes is reset to `pending` and retried (up to `max_attempts`, default 3).

## EventContext

All handlers and rules receive a normalized `EventContext` struct:

```elixir
%EyeInTheSky.Github.EventContext{
  delivery_id: "...",
  event_type: "pull_request.opened",   # event_header.action
  repository_full_name: "owner/repo",
  sender_login: "username",
  pr_number: 42,
  pr_title: "...",
  head_branch: "feature/foo",
  base_branch: "main",
  head_sha: "abc123",
  draft: false,
  merged: false,
  payload: %{...}                       # full raw payload
}
```

## Rules Engine

Rules are rows in `webhook_rules`. Each rule has:

- `event_type` — pattern to match (e.g. `"pull_request.opened"`, `"push"`)
- `repository_full_name` — optional repo filter
- `guard_config` — map of guard flags
- `action` — one of `spawn_agent`, `create_task`, `dm_session`
- `action_config` — action-specific params (agent name, task title, session ID, etc.)

### Guards

| Guard | Behavior |
|-------|----------|
| `ignore_drafts: true` | Skip if PR is a draft |
| `once_per_pr: true` | Skip if a successful execution already exists for this PR |
| `only_if_label: "label"` | Skip unless PR has the given label |
| `max_runs_per_pr: N` | Skip if execution count for this PR >= N |

### Template Interpolation

`action_config` values support `{{variable}}` placeholders resolved from `EventContext`:

```
{{pr_number}}           → 42
{{pr_title}}            → "Fix auth bug"
{{head_branch}}         → "feature/auth-fix"
{{base_branch}}         → "main"
{{repository}}          → "owner/repo"
{{sender}}              → "uriel"
{{head_sha}}            → "abc123..."
```

Invalid variables are rejected at rule-save time.

## PR Subscriptions

Agents can subscribe to a PR and receive a DM for every event that touches it (`pull_request.*`, `check_run.*`, `workflow_job.*`, `push`).

**Commit:** `c8af2c6b`

| Module | Location | Responsibility |
|--------|----------|----------------|
| `PrSubscriptions` | `github/pr_subscriptions.ex` | CRUD: subscribe/3, unsubscribe/3, subscribers_for/2 |
| `PrSubscription` | `github/pr_subscription.ex` | Schema: session_uuid + pr_number + repository_full_name + active |
| `PrSubscriptionController` | `controllers/api/v1/pr_subscription_controller.ex` | POST + DELETE `/api/v1/webhooks/pr_subscriptions` |

Subscribe endpoint:
```bash
POST /api/v1/webhooks/pr_subscriptions
{"pr_number": 42, "repository_full_name": "owner/repo", "session_uuid": "<uuid>"}
# → 201 {id, pr_number, repository_full_name, active}
```

Unsubscribe: `DELETE /api/v1/webhooks/pr_subscriptions` with same body params.

`WebhookDispatcher` fan-outs a DM to each active subscriber after processing each delivery. `EventContext` was extended to extract `pr_number` from `check_run` and `workflow_job` payloads (in addition to `pull_request`). Subscribe/unsubscribe is also available via the CLI: `eits webhooks subscribe` / `eits webhooks unsubscribe`.

`subscribe/3` is idempotent: re-subscribing an inactive subscription re-activates it.

## Database Tables

- `github_webhook_deliveries` — durable inbox, one row per delivery
- `github_webhook_rules` — user-configured trigger rules
- `github_webhook_rule_executions` — audit log, one row per rule fired
- `github_pr_subscriptions` — per-session PR subscriptions (session_uuid, pr_number, repo, active)
- `pull_requests` — extended with `github_pr_id`, `repository_full_name`, `title`, `state`, `draft`, `merged`, `author_login`, `last_synced_at`

## Configuration

```bash
# .env.local (dev)
GITHUB_WEBHOOK_SECRET=        # leave blank when using smee (see Local Dev)

# .env / production
GITHUB_WEBHOOK_SECRET=<secret matching GitHub webhook config>
```

Config key: `Application.get_env(:eye_in_the_sky, :github_webhook_secret)` (set in `config/runtime.exs`).

## Local Dev with smee.io

smee re-encodes webhook bodies as `application/x-www-form-urlencoded` (JSON in a `payload` field), so GitHub's HMAC can never verify against the re-encoded body. The controller handles both cases:

- **Blank secret** → HMAC bypass (use this with smee)
- **smee payload format** → `resolve_payload/1` unwraps `%{"payload" => "<json>"}` automatically

Setup:

```bash
# 1. Install smee client
npm install -g smee-client

# 2. Start forwarding (get your URL from https://smee.io)
smee -u https://smee.io/YOUR_CHANNEL --target http://localhost:5001/api/v1/webhooks/github

# 3. .env.local
GITHUB_WEBHOOK_SECRET=

# 4. GitHub repo → Settings → Webhooks → Add webhook
#    Payload URL:   https://smee.io/YOUR_CHANNEL
#    Content type:  application/json
#    Secret:        (leave blank)
#    Events:        Send me everything

# 5. Restart Phoenix, trigger any GitHub event, check logs for 202
```

Verify rows are landing:

```bash
psql eits_dev -c "SELECT delivery_id, event_type, status FROM github_webhook_deliveries ORDER BY created_at DESC LIMIT 5;"
```

## PubSub Events

| Function | Topic | Payload |
|----------|-------|---------|
| `Events.github_webhook_received/1` | `"github_webhooks"` | `{:github_webhook_received, delivery_id}` |
| `Events.subscribe_github_webhook/0` | subscribes to above | — |
| `Events.pull_request_updated/1` | `"pull_requests"` | `{:pull_request_updated, pull_request}` |
| `Events.subscribe_pull_requests/0` | subscribes to above | — |

# IAM Hook Integration

Claude Code hook events (PreToolUse, PostToolUse, Stop) are forwarded to the EITS IAM
endpoint via a direct `curl` command in `~/.claude/settings.json`. No wrapper script is needed.

**Fail-open guarantee**: `|| true` at the end of the curl command ensures the hook always
exits 0 even if EITS is unreachable. A down EITS server never blocks tool calls.

---

## Prerequisites

- `curl` — must be on `$PATH` when Claude Code runs (`brew install curl` if missing)
- EITS Phoenix server running at `http://127.0.0.1:5001`

---

## Wire the Hooks

Add the following to `~/.claude/settings.json` under each relevant event. The same curl
command works for all events — the IAM controller reads the `event` field from the payload
to determine the hook type.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf --max-time 5 -X POST http://127.0.0.1:5001/api/v1/iam/hook -H 'Content-Type: application/json' -d @- || true"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf --max-time 5 -X POST http://127.0.0.1:5001/api/v1/iam/hook -H 'Content-Type: application/json' -d @- || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf --max-time 5 -X POST http://127.0.0.1:5001/api/v1/iam/hook -H 'Content-Type: application/json' -d @- || true"
          }
        ]
      }
    ]
  }
}
```

Empty `matcher` (`""`) matches all tools. To restrict a hook entry to specific tools, set
`matcher` to a regex: `"Bash|Edit|Write"`.

**PreToolUse is the only blocking event.** PostToolUse and Stop are advisory — missing them
leaves no safety gap.

---

## Port Override

If your EITS server runs on a non-default port, change `5001` in the command accordingly.
The Tauri desktop app reads the `PORT` env variable and rewrites this automatically on startup.

---

## Tauri Desktop — Automatic Installation

The Tauri desktop app automatically installs IAM hooks on every launch via
`install_iam_hooks(&port)` in `src-tauri/src/lib.rs`. It:

1. Reads the current `~/.claude/settings.json`
2. Checks each event type independently for an existing `"iam/hook"` reference
3. Adds the hook entry only if none exists (idempotent — no duplicates)
4. Writes the file back

Port comes from the `PORT` env var (default `5050` in Tauri builds). This means hook
installation is zero-touch for desktop users.

---

## Verify

Start a Claude Code session and trigger any tool call. Check the EITS decision log:

```
http://localhost:5001/iam/decisions
```

You should see a new row with `permission: allow`. To verify a deny is working, enable the
`builtin.block_rm_rf` policy and trigger a Bash call containing `rm -rf` — Claude Code should
block it with the policy message.

You can also query the database directly:

```sql
SELECT session_uuid, tool, resource_path, permission, winning_policy_name, inserted_at
FROM iam_decisions
ORDER BY inserted_at DESC
LIMIT 10;
```

---

## Troubleshooting

**Hooks not firing at all**

Reload Claude Code after editing `settings.json`. Check that the JSON is valid — a parse
error silently disables all hooks.

**EITS unreachable — fail-open in effect**

The `|| true` suffix means the hook exits 0 and Claude continues. Check that `mix phx.server`
is running at `http://127.0.0.1:5001`.

**Agent type not resolving**

If document-based policies aren't firing for a specific agent type, the `session_id` in the
hook payload must match a session that has an associated agent definition slug. Check:

```sql
SELECT s.uuid, ad.slug
FROM sessions s
JOIN agents a ON a.id = s.agent_id
JOIN agent_definitions ad ON ad.id = a.agent_definition_id
WHERE s.uuid = '<your-session-uuid>';
```

If the join returns no rows, the session has no agent definition and `agent_type` will default
to `"*"` — document candidates keyed to a specific slug won't be evaluated.

**Decision log not updating**

The audit write is async (`Task.Supervisor`). If rows are missing, check Phoenix logs for
errors from the `IAMDecisionLogger` task.

**Tool calls blocked unexpectedly**

Query recent denies scoped to your session:

```sql
SELECT tool, resource_path, reason, winning_policy_name, winning_source
FROM iam_decisions
WHERE session_uuid = '<your-session-uuid>'
  AND permission = 'deny'
ORDER BY inserted_at DESC
LIMIT 20;
```

Use the simulator at `/iam/simulator` to replay a context and see which policy matched.

---

## Response Wire Format

The IAM hook endpoint returns JSON consumed directly by Claude Code.

**PreToolUse — allow**:
```json
{"permissionDecision": "allow"}
```

**PreToolUse — deny**:
```json
{
  "permissionDecision": "deny",
  "permissionDecisionReason": "sudo is not permitted by policy 'Block sudo commands'"
}
```
Instruct-policy messages are concatenated into `permissionDecisionReason` alongside the deny reason.

**PostToolUse — instruct match**:
```json
{"additionalContext": "Advisory: this command modifies the database schema…"}
```

**PostToolUse — no match**:
```json
{}
```

**Stop — no instructions**: exits 0 (Claude can stop).
**Stop — instructions present**: exits 2 (blocks Claude from stopping, injects advisory context).

---

## Related

- [IAM_POLICY.md](IAM_POLICY.md) — Policy schema, builtin matchers, evaluator algorithm
- [IAM_POLICY_DOCUMENTS.md](IAM_POLICY_DOCUMENTS.md) — Policy documents and agent type scoping

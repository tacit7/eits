# IAM PreToolUse Hook — Install Guide

The `iam-pretooluse.sh` script wires EITS IAM policy enforcement into every Claude Code
session. On each tool call, Claude Code runs the script with the PreToolUse payload on
stdin; the script forwards it to the EITS IAM decide endpoint and returns the policy
decision (allow or deny) as a Claude hook response.

**Fail-open guarantee:** if EITS is unreachable, the script emits `{"continue": true}`
and exits 0. A failed EITS call will never block a tool use.

---

## Prerequisites

- `curl` — HTTP client
- `jq` — JSON processor

Both must be on `$PATH` when Claude Code runs. Install via your system package manager
if missing (`brew install curl jq` on macOS).

---

## Step 1 — Set EITS_URL

The script reads `$EITS_URL` to locate the API. Set it in your shell profile:

```bash
# ~/.zshrc or ~/.bashrc
export EITS_URL=http://localhost:5001/api/v1
```

If `EITS_URL` is not set, the script defaults to `http://localhost:5001/api/v1`.

---

## Step 2 — Wire into settings.json

Add the script to the `PreToolUse` hooks array in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/eits/web/priv/scripts/iam-pretooluse.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `/path/to/eits/web` with the absolute path to this repo. The empty `matcher`
field matches all tools. To restrict enforcement to specific tools, set `matcher` to a
regex (e.g., `"Bash|Edit|Write"`).

**Example with multiple hooks** (IAM runs after the existing EITS workflow guard):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/eits/web/priv/scripts/eits-pre-tool-use.sh"
          },
          {
            "type": "command",
            "command": "/path/to/eits/web/priv/scripts/iam-pretooluse.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Step 3 — Verify

Start a Claude Code session. Trigger any tool call. In the EITS web UI at
`http://localhost:5001/iam/decisions`, you should see a new `iam_decisions` row with
`permission: allow` (assuming no deny policies are active).

To verify a deny: with the `block_rm_rf` built-in policy enabled, run a Bash tool call
containing `rm -rf`. Claude Code should block the call with the policy's reason message.

---

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `EITS_URL` | `http://localhost:5001/api/v1` | API base URL for the EITS server |

---

## Troubleshooting

**Hook not firing at all**

Check that the path in `settings.json` is absolute and the script is executable:

```bash
chmod +x /path/to/eits/web/priv/scripts/iam-pretooluse.sh
```

Reload Claude Code after editing `settings.json`.

**Endpoint unreachable — fail-open in effect**

The script logs to stderr when it fails open:

```
[iam-pretooluse] fail-open: endpoint returned HTTP 000
```

To see these messages, start Claude Code from a terminal. If EITS is not running,
start the Phoenix server:

```bash
cd /path/to/eits/web
mix phx.server
```

**Decision log not updating**

The endpoint writes to `iam_decisions` asynchronously via `Task.Supervisor`. If the
table is empty after a confirmed allow, check Phoenix logs for audit write errors.

**Tool calls blocked unexpectedly**

Query recent deny decisions:

```sql
SELECT session_uuid, tool, resource_path, reason, winning_policy_name
FROM iam_decisions
WHERE permission = 'deny'
ORDER BY inserted_at DESC
LIMIT 20;
```

Or filter by your session UUID to see only your calls.

---

## Phase 4a: Policy Evaluation with Built-in Matchers

Starting with Phase 4a, system policies can use `builtin_matcher` for specialized detection
beyond regex conditions. When a policy has a builtin matcher set:

1. **Conditions are evaluated first** (AND logic)
2. **If conditions match, builtin_matcher is dispatched**
   - Dispatched via `safe_builtin_match/2` with rescue/catch protection
   - Error in matcher → returns false (fail closed, does not match)
   - Builtin matcher returns true/false
3. **Both conditions AND builtin_matcher must match** for policy to apply

### Builtin Matcher Keys

System policies can set `builtin_matcher` to one of these registered keys:

```json
[
  "block_sudo",
  "block_rm_rf",
  "protect_env_vars",
  "block_env_files",
  "block_read_outside_cwd",
  "block_push_master",
  "block_curl_pipe_sh",
  "block_work_on_main",
  "warn_destructive_sql"
]
```

Each key corresponds to a specialized Elixir module that can:
- Parse command arguments
- Resolve file paths
- Inspect git state
- Analyze SQL statements
- Access environment variables

### Example Policy with Builtin Matcher

```json
{
  "name": "Block rm -rf",
  "description": "Prevent destructive rm -rf commands",
  "action": "deny",
  "system_key": "builtin.block_rm_rf",
  "builtin_matcher": "block_rm_rf",
  "conditions": [
    {
      "kind": "tool_name_match",
      "value": "Bash"
    }
  ]
}
```

When Claude Code runs a Bash command:
1. Condition `tool_name_match: "Bash"` is evaluated
2. If matched, `builtin_matcher: "block_rm_rf"` is dispatched
3. The BlockRmRf module parses the command and detects `rm -rf` patterns
4. If detected, policy action `"deny"` blocks the call

### Important: Command/Content Regex

Only **system policies with registered builtin matchers** can use command/content parsing and 
git-state inspection. User-authored policies in v1 cannot set `builtin_matcher` and are 
restricted to declarative conditions (regex only).

---

## How the response adapter works

The EITS endpoint calls `EITS.IAM.HookResponse.to_json/2`, which maps the `Decision`
struct to the Claude hook wire format:

- **PreToolUse** — returns `permissionDecision: "allow" | "deny"` plus
  `permissionDecisionReason` from the winning policy message. Advisory instructions
  from `instruct` policies are concatenated into the reason.
- **PostToolUse** — returns `additionalContext` with accumulated advisory output.
- **Stop** — returns exit-code semantics; code 2 blocks Claude from stopping when
  instructions are present.

The hook script passes the raw PreToolUse payload through unchanged and forwards the
adapter's JSON directly to stdout for Claude Code to consume.

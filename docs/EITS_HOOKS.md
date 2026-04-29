# EITS Hook Scripts

Claude Code integration scripts that manage session lifecycle, context injection, and tool-use enforcement.

**Location:** `priv/scripts/eits-*.sh`
**Registered in:** `~/.claude/settings.json`

---

## How Context Injection Works

Context injection differs by hook type:

**SessionStart hooks** — anything printed to `stdout` is automatically injected into Claude's context.

```bash
echo "$CONTEXT"   # injected directly into conversation context
```

**Turn-based hooks** (`PreToolUse`, `PostToolUse`, `Stop`) — use `hookSpecificOutput` in a JSON response:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "...markdown string..."
  }
}
```

`PreToolUse` hooks use `permissionDecision` to allow or deny tool calls instead of `additionalContext`.

---

## CLAUDE_ENV_FILE

`SessionStart` and `SessionStart(resume)` hooks write environment variables to a temp file at `$CLAUDE_ENV_FILE`. These vars persist for the entire session and are available to all subsequent Bash tool calls.

```bash
echo "EITS_SESSION_UUID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"
echo "EITS_AGENT_UUID=$AGENT_UUID"   >> "$CLAUDE_ENV_FILE"
echo "EITS_PROJECT_ID=$PROJECT_ID"   >> "$CLAUDE_ENV_FILE"
```

| Variable | Set By | Purpose |
|---|---|---|
| `EITS_SESSION_UUID` | startup / resume | Session UUID for all API calls |
| `EITS_AGENT_UUID` | startup (pre-registered) / resume | Agent UUID |
| `EITS_PROJECT_ID` | startup / resume | Resolved project integer ID |
| `EITS_URL` | startup | REST API base URL |
| `EITS_ENTRYPOINT` | startup / resume | CLI entrypoint identifier |

---

## Workflow Guard

Every hook checks the `EITS_WORKFLOW` env var before doing any work:

```bash
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
```

Set `EITS_WORKFLOW=0` to disable all hook behavior for a session.

---

## Session Lifecycle Hooks

### SessionStart (startup / clear) — `eits-session-startup.sh`

Fires when a new session starts or is cleared (`/clear`).

**What it does:**
1. Calls `eits sessions get $SESSION_ID` to check for a pre-registered session (spawned by workable task worker)
2. Resolves or creates the project via `eits projects list` / `eits projects create` by path
3. Writes env vars to `$CLAUDE_ENV_FILE`: `EITS_URL`, `EITS_SESSION_UUID`, `EITS_ENTRYPOINT`, `EITS_AGENT_UUID` (if pre-registered), `EITS_PROJECT_ID`
4. Patches entrypoint on pre-registered sessions via `eits sessions update`
5. Writes `$SESSION_ID` to `.git/eits-session` (used by post-commit hook)
6. Updates session status to `working` via `eits sessions update --status working`
7. Echoes a `$CONTEXT` markdown block to stdout for injection

**Context injected (new sessions):**
```
# Eye in the Sky Integration Active
**IMPORTANT**: Immediately invoke the Skill tool with `skill: "eits-init"` ...
```

**Context injected (pre-registered / spawned sessions):**
```
Session pre-registered. EITS_AGENT_UUID is already set — skip /eits-init.
```

---

### SessionStart (resume) — `eits-session-resume.sh`

Fires when an existing session is resumed.

**What it does:**
1. Calls `eits sessions get $SESSION_ID` — returns `id`, `agent_int_id`, `agent_id`, `name`, `project_id`
2. Resolves project via `eits projects list` / `eits projects create` if `project_id` is null
3. Writes/overwrites env vars in `$CLAUDE_ENV_FILE` (resume always wins)
4. Patches entrypoint via `eits sessions update --entrypoint`
5. Writes session/agent UUIDs to `.git/eits-session` / `.git/eits-agent`
6. Updates session status to `working` via `eits sessions update --status working`
7. Echoes `$CONTEXT` markdown to stdout for injection

---

### SessionStart (compact) — `eits-session-compact.sh`

Fires after context compaction completes.

**What it does:**
- Sets session status back to `working` via `eits sessions update`

> Also followed by `eits-session-startup.sh` in the compact hook chain (see settings.json).

---

### SessionEnd — `eits-session-end.sh`

Fires when the session window closes.

**What it does:**
1. Lists in-progress tasks for the session via `eits tasks list --session $session_id --state 2`
2. Moves each to In Review (`state_id=4`) via `eits tasks update --state 4`
3. Marks session as `completed` via `eits sessions update --status completed`

---

### Stop — `eits-session-stop.sh`

Fires after every Claude turn completes.

**What it does:**
- Sets session status to `idle` via `eits sessions update --status idle`
- Guards against infinite loops via `stop_hook_active` field in input JSON

---

## Tool-Use Hooks

### PreToolUse (Edit|Write) — `eits-pre-tool-use.sh`

Fires before any `Edit` or `Write` tool call. Enforces the EITS workflow.

**What it does:**
1. Calls `eits sessions get` — fails open if API is unreachable
2. **Non-spawned sessions**: denies if session has no name (requires `/eits-init`)
3. **Non-spawned sessions**: denies if no active task (`state_id=2`) via `eits tasks list --session $session_id --state 2 --json` (JSON output required for jq parsing)

**Deny response format:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "..."
  }
}
```

Spawned agents bypass all checks.

---

### PostToolUse (Bash) — `eits-post-tool-commit.sh`

Fires after every Bash tool call. Filters for git commit commands.

**What it does:**
1. Checks `tool_input.command` contains `git commit` — exits immediately if not
2. Reads the commit hash via `git rev-parse HEAD` in `$CLAUDE_PROJECT_DIR`
3. Logs commit to EITS via `eits commits create --hash $HASH --message $MSG`

Silent — exits 0, no feedback to Claude.

---

### PostToolUse (all) — `eits-post-tool-use.sh`

No-op placeholder, reserved for future tool result tracking.

---

### UserPromptSubmit — `eits-prompt-submit.sh`

Fires before Claude processes each user prompt.

**What it does:**
- Sets session to `working` via `eits sessions update --status working` (async)

---

## Utility Hooks

### `eits-agent-working.sh`

Sets session to `working` on SessionStart. Runs alongside startup/resume/clear in settings.json.

### `eits-pre-compact.sh`

Sets session to `compacting` before context compaction begins so the UI can show a reason for slow response.

---

## settings.json Registration

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup", "hooks": [
        { "command": "eits-session-startup.sh" },
        { "command": "eits-agent-working.sh" }
      ]},
      { "matcher": "resume", "hooks": [
        { "command": "eits-session-resume.sh" },
        { "command": "eits-agent-working.sh" }
      ]},
      { "matcher": "compact", "hooks": [
        { "command": "eits-session-compact.sh" },
        { "command": "eits-session-startup.sh" }
      ]},
      { "matcher": "clear", "hooks": [
        { "command": "eits-session-startup.sh" },
        { "command": "eits-agent-working.sh" }
      ]}
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "command": "eits-pre-tool-use.sh" }] },
      { "hooks": [{ "command": "eits-nats-tool-pre.sh", "async": true }] }
    ],
    "PostToolUse": [
      { "hooks": [{ "command": "eits-post-tool-use.sh" }] },
      { "matcher": "Bash", "hooks": [{ "command": "eits-post-tool-commit.sh" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "command": "eits-prompt-submit.sh", "async": true }] }
    ],
    "PreCompact": [
      { "hooks": [{ "command": "eits-pre-compact.sh", "async": true }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "command": "eits-session-end.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "command": "eits-session-stop.sh" }] }
    ]
  }
}
```

---

## Cleanup TODO

- Remove `eits-nats-tool-pre.sh` from settings.json and delete the script — NATS is no longer used
- Remove `.git/hooks/post-commit` (`eits-post-commit.sh`) to avoid double-logging commits now that `eits-post-tool-commit.sh` handles it via Claude Code hooks

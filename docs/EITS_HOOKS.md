# EITS Hook Scripts

Claude Code and Codex integration scripts that manage session lifecycle,
context injection, task workflow enforcement, and tool-use guardrails.

**Claude script location:** `priv/scripts/eits-*.sh` (canonical) → installed
to `~/.config/eits/hooks/`
**Claude registration:** `~/.claude/settings.json`
**Codex registration:** `.codex/hooks.json` → symlink to
`priv/hooks/codex/hooks.json`

---

## Installation

### Claude Code

EITS hooks are automatically registered using the `eits hooks install` command:

```bash
eits hooks install
```

This command:
1. **Copies hook scripts** from `priv/scripts/` to `~/.config/eits/hooks/` (preserves permissions)
2. **Installs the eits CLI** to `~/.local/bin/eits` for global availability
3. **Updates your shell profile** (`~/.zprofile` / `~/.bash_profile`) to add `~/.local/bin` to `PATH`
4. **Merges hook entries** into `~/.claude/settings.json` without overwriting existing unrelated settings
5. **Reports what was installed** and when to open a new terminal for PATH changes to take effect

### Uninstalling

```bash
eits hooks uninstall
```

Removes all EITS-managed hook entries from `~/.claude/settings.json` but leaves scripts and CLI binary in place.

---

### Codex

Codex hooks are project-scoped. The repo-owned hook configuration is:

```bash
priv/hooks/codex/hooks.json
```

The project should expose it through `.codex/hooks.json`:

```bash
mkdir -p .codex
ln -sfn ../priv/hooks/codex/hooks.json .codex/hooks.json
```

Codex must also have hooks enabled in `~/.codex/config.toml`:

```toml
[features]
hooks = true
```

Codex hooks use the same Rust-first `eits` CLI as agents and humans. Do not
document or add new direct hook calls to `eitsr` or `scripts/eits-extras`; the
legacy extras path is an internal fallback owned by the Rust CLI.

---

## Session Status Lifecycle

Status transitions are driven by **two layers**: the Elixir backend and
provider hooks. Understanding which layer does what is critical.

### Backend (Elixir — `agent_worker_events.ex`)

`on_sdk_completed/3` fires inside the AgentWorker process after every Claude turn. It is the **primary** source of `working → idle` transitions — it runs before any bash Stop hooks and writes directly to the DB.

**Key behavior (as of 2026-07-11):** `on_sdk_completed` only writes `idle` if the session is currently `working`. If an agent explicitly set a different status during its turn (e.g. `waiting`), that status is preserved. Callers: `Events.agent_stopped` and `notify_agent_status` still fire regardless, so the UI always reflects the turn end.

### Hooks (bash)

Hooks handle the secondary status transitions around session start, turn start,
turn stop, compaction, session end, and error cases.

| Status | Source | Trigger |
|--------|--------|---------|
| `working` | Claude `UserPromptSubmit` hook (`eits-prompt-submit.sh`) | Each user prompt |
| `working` | Codex `UserPromptSubmit` hook (`codex-prompt-working.sh`) | Each user prompt |
| `working` | Claude `SessionStart` hook (`eits-session-startup.sh` / `eits-session-resume.sh`) | Session start/resume |
| `idle` | AgentWorker backend (`on_sdk_completed`) | Turn completes, only if currently `working` |
| `idle` | Codex `SessionStart` via dispatcher | Codex session is registered but no prompt is running yet |
| `idle` | Codex `Stop` hook (`codex-session-stop.sh`) | Codex turn stops |
| `waiting` | `SessionEnd` hook (`eits-session-end.sh`) for `sdk-cli` | Process exits |
| `completed` | `SessionEnd` hook (`eits-session-end.sh`) for `cli` | Process exits |
| `failed` | AgentWorker (`on_max_retries_exceeded` / `on_session_failed`) | Error |
| `compacting` | `PreCompact` hook (`eits-pre-compact.sh`) | Before compaction |

---

## Context Injection

**SessionStart hooks** — anything printed to `stdout` is injected into Claude's context.

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

Codex does not use `CLAUDE_ENV_FILE`, but it still receives the SessionStart
context block printed by `eits-session-startup.sh` through the Codex hook
dispatcher.

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

## Codex Env Files

Codex has no `CLAUDE_ENV_FILE` equivalent. During Codex `SessionStart`,
`eits-codex-notify.sh` dispatches to `eits-session-startup.sh`, which writes a
session-specific env file:

```bash
~/.eits/codex/sessions/<session_id>.env
```

The file is mode `0600`, lives under a mode `0700` directory, and stores
non-secret session identity:

| Variable | Purpose |
|---|---|
| `EITS_URL` | REST API base URL |
| `EITS_SESSION_UUID` | Codex session/thread UUID |
| `EITS_SESSION_ID` | Integer EITS session ID, when resolved |
| `EITS_AGENT_UUID` | Agent UUID, when resolved |
| `EITS_AGENT_ID` | Integer agent ID, when resolved |
| `EITS_PROJECT_ID` | Integer project ID, when resolved |

The Rust `eits` CLI auto-loads this file when `EITS_CODEX_SESSION_ID`,
`CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set. If a Codex session has no
session id available, the agent should ask the user for it rather than guessing.

---

## Workflow Guard

Every hook checks the `EITS_WORKFLOW` env var before doing any work:

```bash
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
```

Set `EITS_WORKFLOW=0` to disable all hook behavior for a session.

---

## Session Lifecycle Hooks

### Codex Dispatcher — `eits-codex-notify.sh`

Codex runs one dispatcher hook for lifecycle, compaction, tool-use, and stop
events. The dispatcher loads `~/.eits/codex/sessions/<session_id>.env` when it
can infer a session id from `EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or
`CODEX_SESSION_ID`, then maps Codex payloads to the shared EITS hook scripts.

| Codex event | Dispatcher behavior |
|---|---|
| `SessionStart` `startup` / `clear` | Runs `eits-session-startup.sh` with `EITS_SESSION_START_STATUS=idle` |
| `SessionStart` `resume` | Runs `eits-session-resume.sh` with `EITS_SESSION_START_STATUS=idle` |
| `SessionStart` `compact` | Runs `eits-session-compact.sh`, `eits-session-startup.sh`, and `eits-agent-working.sh` |
| `UserPromptSubmit` | Runs `codex-prompt-working.sh` |
| `PreToolUse` `Edit` / `Write` / `apply_patch` | Runs `eits-pre-tool-use.sh` |
| `PreToolUse` `Bash` | Runs `eits-rm-worktree-guard.sh` |
| `PreToolUse` all matched tools | Runs `eits-nats-tool-pre.sh` after the tool-specific guard |
| `PostToolUse` | Runs `eits-post-tool-use.sh` and `codex-post-commit.sh` |
| `PreCompact` | Runs `eits-pre-compact.sh` |
| `PostCompact` | Runs `eits-post-compact.sh` |
| `SessionEnd` | Runs `eits-session-end.sh` |
| `Stop` | Runs `codex-session-stop.sh` |

The dispatcher also sets `CLAUDE_CODE_ENTRYPOINT` from `EITS_ENTRYPOINT` for
shared scripts that still branch on the Claude variable.

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

For Codex, the dispatcher sets `EITS_SESSION_START_STATUS=idle` so a newly
opened or resumed Codex session appears idle until `UserPromptSubmit` marks it
working. The same startup script also writes the Codex env file described above.

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

Fires once when the Claude CLI process exits.

**What it does:**
1. Lists in-progress tasks for the session via `eits tasks list --session $session_id --state 2`
2. Moves each to In Review (`state_id=4`) via `eits tasks update --state 4`
3. **Status transition** — only if current status is `working` or unknown:
   - `cli` (interactive) → `completed`
   - `sdk-cli` (headless/spawned) → `waiting` (session can be resumed)

> **Note:** The status guard prevents clobbering a status the agent explicitly set (e.g. the agent called `eits sessions update --status waiting` during its last turn — that survives).

---

### Stop (1) — `eits-session-stop.sh`

Fires after every Claude turn. Runs first in the Stop chain.

**Section 1 — Task annotation enforcement (blocking)**

Parses the current turn's transcript. If the agent used mutating tools (Edit/Write/MultiEdit/Bash with side effects) but never called `eits tasks annotate/update/complete`:
- Blocks the turn with `exit 2`
- Prints the task ID, title, and the exact commands to fix it

Read-only turns (Read/Grep/WebSearch) and DM-only Bash calls are always exempt.

**Section 2 — sdk-cli idle transition**

If `CLAUDE_CODE_ENTRYPOINT=sdk-cli`, reads current session status and sets it to `idle` if still `working`. Runs in the background, never blocks. Belt-and-suspenders alongside the AgentWorker backend — prevents sessions from getting stuck in `working` when a turn ends without a clean `on_sdk_completed` event. Status guard: only fires if currently `working` — won't clobber `waiting`/`completed`/`failed`.

**Section 3 — Team notification (non-blocking, background)**

If this session belongs to an active team:
1. Queries `GET /api/v1/teams?status=active` for all active teams
2. Checks each team's member list for this session
3. DMs all members with `role=orchestrator`; falls back to all other members if no orchestrator role is set
4. Message: `"Turn complete. Task #<id>: <title>"`

Runs in the background — never delays the turn.

---

### Stop (2) — `eits-stop-auto-close-tasks.sh`

Fires after `eits-session-stop.sh`. Safety net for tasks left open.

**What it does:**
- Finds in-progress tasks linked to the session
- Auto-completes each with `"Auto-closed at session stop."`
- Guards against infinite loops via `stop_hook_active`

> If `eits-session-stop.sh` blocked with `exit 2`, this hook still runs — Claude Code continues the Stop chain regardless of individual hook exit codes unless the chain is configured to abort on failure.

---

## Tool-Use Hooks

### Codex IAM Guard — `codex-iam-guard.sh`

Codex `PreToolUse`, `PostToolUse`, and `Stop` groups also run
`codex-iam-guard.sh`. It posts the raw Codex hook payload to
`$EITS_URL/iam/decide` and adapts the backend response to Codex-compatible
hook output.

Behavior:

1. Fails open when `curl`, `jq`, stdin JSON, or the IAM endpoint is unavailable.
2. Preserves `PreToolUse` denies as `permissionDecision: "deny"`.
3. Preserves advisory `additionalContext` when returned by IAM.
4. Converts blocking `PostToolUse` / `Stop` results into Codex
   `{ "decision": "block", "reason": "..." }` output.
5. Suppresses Claude-only allow/fail-open fields that Codex may reject.

### PreToolUse (Edit|Write) — `eits-pre-tool-use.sh`

Fires before any `Edit` or `Write` tool call. Enforces the EITS workflow.

**What it does:**
1. Calls `eits sessions get` — fails open if API is unreachable
2. **Non-spawned sessions**: denies if session has no name (requires `/eits-init`)
3. **Non-spawned sessions**: denies if no active task (`state_id=2`) via `eits tasks list --session $session_id --state 2`

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

### Codex PostToolUse Commit Logging — `codex-post-commit.sh`

Codex also runs `codex-post-commit.sh` after `PostToolUse`. It reads the Codex
payload shape (`tool_name` and `tool_input.command`), filters for Bash commands
that contain `git commit`, resolves `HEAD` in `EITS_PROJECT_DIR` or the current
directory, and calls:

```bash
eits commits create --hash "$HASH" --message "$MSG"
```

Failures are intentionally ignored so commit logging never blocks the turn.

---

### UserPromptSubmit — `eits-prompt-submit.sh`

Fires before Claude processes each user prompt.

**What it does:**
- Sets session to `working` via `eits sessions update --status working` (async)

### Codex UserPromptSubmit — `codex-prompt-working.sh`

Fires before Codex processes each user prompt.

**What it does:**
- Reads `session_id` from the Codex hook payload.
- Sets that session to `working` via `eits sessions update --status working`
  in the background.

### Codex Stop — `codex-session-stop.sh`

Fires after a Codex turn stops.

**What it does:**
1. Ignores recursive stop-hook payloads with `stop_hook_active=true`.
2. Lists in-progress tasks linked to the Codex session.
3. Blocks with exit `2` if any in-progress task exists, because Codex has no
   transcript path equivalent for checking whether the task was annotated this
   turn.
4. Sets the session to `idle` in the background.

---

## Utility Hooks

### `eits-agent-working.sh`

Sets session to `working` on SessionStart. Runs alongside startup/resume/clear in settings.json.

### `eits-pre-compact.sh`

Sets session to `compacting` before context compaction begins so the UI can show a reason for slow response.

---

## Current settings.json Registration

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup", "hooks": [
        { "command": "~/.config/eits/hooks/eits-session-startup.sh" },
        { "command": "~/.config/eits/hooks/eits-agent-working.sh" }
      ]},
      { "matcher": "resume", "hooks": [
        { "command": "~/.config/eits/hooks/eits-session-resume.sh" },
        { "command": "~/.config/eits/hooks/eits-agent-working.sh" }
      ]},
      { "matcher": "compact", "hooks": [
        { "command": "~/.config/eits/hooks/eits-session-compact.sh" },
        { "command": "~/.config/eits/hooks/eits-session-startup.sh" }
      ]},
      { "matcher": "clear", "hooks": [
        { "command": "~/.config/eits/hooks/eits-session-startup.sh" },
        { "command": "~/.config/eits/hooks/eits-agent-working.sh" }
      ]}
    ],
    "SessionEnd": [
      { "hooks": [{ "command": "~/.config/eits/hooks/eits-session-end.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "command": "~/.config/eits/hooks/eits-session-stop.sh" }] },
      { "hooks": [{ "command": "~/.config/eits/hooks/eits-stop-auto-close-tasks.sh" }] },
      { "matcher": "", "hooks": [{ "type": "command", "command": "curl -sf --max-time 5 -X POST http://127.0.0.1:34877/api/v1/iam/hook -H 'Content-Type: application/json' -d @- || true" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "command": "~/.config/eits/hooks/eits-prompt-submit.sh", "async": true }] }
    ],
    "PreToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "curl -sf --max-time 5 -X POST http://127.0.0.1:34877/api/v1/iam/hook -H 'Content-Type: application/json' -d @- || true" }] }
    ],
    "PostToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "curl -sf --max-time 5 -X POST http://127.0.0.1:34877/api/v1/iam/hook -H 'Content-Type: application/json' -d @- || true" }] }
    ]
  }
}
```

> **Note:** The IAM curl hook (`http://127.0.0.1:34877/api/v1/iam/hook`) handles PreToolUse, PostToolUse, and Stop. It enforces IAM policies — see [IAM_HOOK_INSTALL.md](IAM_HOOK_INSTALL.md) for details.

## Current Codex hooks.json Registration

The repo-owned Codex registration lives at `priv/hooks/codex/hooks.json`.
Project checkouts should expose it through `.codex/hooks.json` as a symlink.
Commands are intentionally repo-absolute in the generated JSON today.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 15
          },
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/codex-iam-guard.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 15
          },
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/codex-iam-guard.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/eits-codex-notify.sh",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "bash /Users/urielmaldonado/projects/eits/web/priv/scripts/codex-iam-guard.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

# eits CLI

Bash script at `scripts/eits`. Talks to the Eye in the Sky REST API.

## Setup

```bash
# Default URL
export EITS_URL=http://localhost:5001/api/v1

# Optional auth
export EITS_API_KEY=<your-key>

# Injected automatically by EITS hooks — set manually if needed
export EITS_SESSION_UUID=<session-uuid>
export EITS_SESSION_ID=<session-id>          # numeric session ID, exported by startup hook (preferred for --to/--from/--parent-session-id)
export EITS_AGENT_UUID=<agent-uuid>
export EITS_PROJECT_ID=<project-id>
```

Requires `curl` and `jq`.

**Fallback order** for session identification (when command requires a session but env var unset):
1. `$EITS_SESSION_UUID` (primary)
2. `$EITS_SESSION_ID` (integer fallback)

Pass `--help` to any subcommand for usage details (e.g. `eits tasks --help`, `eits dm --help`).

### JSON parsing

The script's internal `json()` helper coerces numeric values only for keys whose name ends in `_id` (e.g. `task_id`, `project_id`, `session_id`). Other numeric-looking fields (hashes, freeform numeric strings) are preserved as-is, preventing unintended integer/float conversion.

`AUTH_HEADER` is internally an array so multiple `-H` flags can be passed to `curl` without quoting issues. Do not treat it as a scalar when editing the script.

### Rate limiting

The script has built-in **3-retry logic for HTTP 429 (rate limited)** errors. You'll see:
```
rate limited, retrying in 1s...
rate limited, retrying in 2s...
```

If all 3 attempts fail, the command exits with HTTP 429 error.

**Phase 1 — Orchestrator bump**: When `EITS_SESSION_UUID` is set, the script sends the `x-eits-role: orchestrator` header to get a 5× higher rate-limit burst ceiling (keyed separately as `api:orch:<ip>` so orchestrator traffic doesn't consume the regular IP bucket).

**Phase 2 — Per-session bucket**: When `EITS_SESSION_UUID` is set, the script sends `x-eits-session: $EITS_SESSION_UUID` at all curl sites. If the server's `rate_limit_per_session` setting is enabled AND the header matches an existing session, the request uses a per-session bucket (`api:sess:<uuid>`) with a 60-req/10s burst limit so co-located agents don't starve each other. This header is safe to send; the server ignores it when the flag is off or the session UUID is unknown, falling back to Phase 1 behavior.

Each rate-limit evaluation emits a `[:eits, :rate_limit, :check]` telemetry event with `{remaining, limit}` measurements and `{bucket, bucket_kind, session_id, status}` metadata.

---

## sessions

```bash
eits sessions list [--search <q>] [--name <partial>] [--status <s>] \
  [--project <id>] [--agent <uuid>] [--parent <id|uuid>] [--mine] \
  [--limit <n>] [--include-archived] [--with-tasks]

eits sessions get <uuid>
eits sessions get self                         # Use current $EITS_SESSION_UUID

eits sessions create --session-id <uuid> [--name <n>] [--description <d>] \
  [--project <name>] [--model <m>] [--entrypoint <e>]

eits sessions update <uuid> [--status <s>] [--intent <text>] \
  [--entrypoint <e>] [--name <name>] [--description <desc>] \
  [--clear-entrypoint] [--ended-at <ISO8601>]

eits sessions end <uuid> [--final-status <completed|failed|waiting>]

eits sessions archive <uuid>

eits sessions unarchive <uuid>

eits sessions context <uuid> [--text <text>|--from-stdin] [--metadata <json>]

eits sessions tasks <uuid>     # List tasks linked to session

eits sessions notes <uuid> [<note_id>] [--full] [--starred] \
  [--add <body>] [--title <t>]
# Default: preview listing (title + 100 char snippet + size + date)
# <note_id>: show full body of a single note
# --full: dump full bodies for all notes
# --starred: filter to starred notes only
# --add: create a new note on this session

eits sessions reopen [<uuid|self>]
# Clears ended_at, sets status to idle.
# Defaults to $EITS_SESSION_UUID when uuid omitted.
# 'self' is substituted with $EITS_SESSION_UUID at call time.
# Use when resume hook fails or when an orchestrator needs to post work
# against an already-ended session.
```

`--status` filters by session status: `working`, `idle`, `waiting`, `completed`, `failed`.

`--parent <id|uuid>` filters child sessions by parent session ID. Accepts integer ID or UUID. Independent of other filters.

`--mine` is mutually exclusive with `--agent`, `--search`, `--status`, `--project`.

`--parent` is independent and can combine with any other filter.

`sessions get <uuid>` returns a rich response that includes the session, linked tasks, notes (last 5, body truncated), and commits (last 5) in a single call.

---

## tasks

```bash
# List / filter
eits tasks list [--project <id>] [--session <uuid>] [--q <query>|--search <query>] \
  [--state <id>] [--state-name <todo|in-progress|done|in-review>] \
  [--agent <uuid>] [--mine|--assigned] [--created-by] [--all] [--limit <n>]
# Default: lists only current session's tasks when EITS_SESSION_UUID is set
# --all: override to list across all sessions
# --mine / --assigned: tasks where current session is the active executor (linked via task_sessions after claim)
# --created-by: tasks created by the current session (via created_by_session_id)

eits tasks active [--json]
eits tasks mine [--json]
# Show In Progress tasks linked to current session (useful for context recovery on resume)
# Uses EITS_SESSION_UUID (or EITS_SESSION_ID as fallback)

# Get
eits tasks get <id>

# Create
eits tasks create --title <t> [--description <d>] [--project <id>] \
  [--priority <p>] [--session <uuid>] [--agent <uuid>] \
  [--tags <id1,id2,...>] [--team <id>] [--due-at <ISO8601>]
# Defaults: --agent from $EITS_AGENT_UUID, --project from $EITS_PROJECT_ID, --session from $EITS_SESSION_UUID

# Create + start in one shot
eits tasks begin --title <t> [--description <d>] [--project <id>] \
  [--priority <p>] [--quiet|-q]
# Or claim a pre-created task instead of creating new
# On conflict (already_claimed), shows the holding session ID, UUID, and name
eits tasks begin --id <task_id>

# Update
eits tasks update <id> [--state <id|name>] \
  [--priority <p>] [--title <t>] [--description <d>] [--due-at <ISO8601>]
# State IDs: 1=To Do, 2=In Progress, 3=Done, 4=In Review
# State names (aliases): todo, start|in-progress|progress, done, review|in-review

# Bulk update
eits tasks bulk-update --ids <id,...> [--state <id>] [--priority <p>] [--title <t>]

# State shorthands (canonical)
eits tasks claim <id>          # → In Progress (state 2), transfers session ownership to claimer (preferred)
                               # Removes all existing task_sessions links, adds claimer's session atomically
eits tasks complete <id> <message>  # Annotate + mark done + DM lead (preferred)

# Deprecated aliases (kept for backwards compatibility, emit warning to stderr)
eits tasks start <id>          # DEPRECATED: use claim instead
eits tasks done <id>           # DEPRECATED: use complete instead

# Complete with message (canonical close: annotate + mark Done in one call)
eits tasks complete <id> <message>
eits tasks complete <id> --message <text>
eits tasks complete <id> --message <text> --commit <sha>
# --commit: track a commit atomically with task close (eliminates a separate eits commits create round-trip)
# --notify <session_uuid_or_id>: DM a session after successful close

# Delete
eits tasks delete <id>

# Annotations (retries on 429 with 2s/4s/8s backoff; queues to ~/.eits/pending-annotations.log on failure)
eits tasks annotate <id> --body <text> [--title <t>]

# Session linking
eits tasks link-session <task_id> [<session_uuid>]     # defaults to $EITS_SESSION_UUID
eits tasks unlink-session <task_id> <session_uuid>

# Search
eits tasks search <query> [--project <id>] [--limit <n>] [--state <id>]

# List sessions linked to a task
eits tasks sessions <id>

# Tag a task
eits tasks tag <task_id> <tag_id>

# List workflow states
eits tasks states
```

### Exit codes

`tasks list` and other table-printing commands are safe to use in scripts with `set -euo pipefail`. The `[[ cond ]] && cmd` pattern was replaced with `if/fi` guards so empty-result branches no longer exit 1 under pipefail. This applies to `_tbl_tasks`, `_tbl_sessions`, `_tbl_notes`, `_tbl_commits`, `channels list`, and `channels members`.

### Workflow states

| ID | Name        |
|----|-------------|
| 1  | To Do       |
| 2  | In Progress |
| 4  | In Review   |
| 3  | Done        |

### Agent task workflow (canonical)

**Option 1: Create new task (agent-initiated)**
```bash
eits tasks begin --title "Implement X"              # create + start in one shot
eits tasks update 42 --state-name in-review        # move to review when ready
eits tasks complete 42 "Implemented feature X"     # CANONICAL close: annotate + mark Done + DM lead
eits tasks complete 42 --message "done" --commit $SHA  # close + track commit atomically
```

**Option 2: Claim pre-created task (orchestrator-assigned)**
```bash
eits tasks begin --id 42                           # claim task 42 (no title required)
                                                   # conflict: shows holding session ID, UUID, name
eits tasks update 42 --state-name in-review        # move to review when ready
eits tasks complete 42 "Implemented feature X"     # CANONICAL close
```

**Manual close (two round-trips, avoid if possible)**
```bash
eits tasks annotate 42 --body "Work summary"
eits tasks update 42 --state done                  # or --state 3, or --state-name done
```

---

## queue

```bash
eits queue status                 # Print pending annotation count + per-task summary

eits queue flush                  # Replay ~/.eits/pending-annotations.log, drop successes, keep failures
                                  # Exits non-zero if anything remains
```

When `eits tasks annotate` encounters persistent HTTP 429 (rate limited) errors, the annotation is queued to `~/.eits/pending-annotations.log` (JSONL format). Use `queue status` to see what's pending, and `queue flush` to retry all pending annotations.

---

## search

```bash
eits search <query> [--type <csv>] [--limit <n>] [--project <id>] [--json]
# Full-text search across sessions, tasks, and notes in one shot

# Options:
#   --type <csv>    Entity types to search, comma-separated (default: sessions,tasks,notes)
#   --limit <n>     Max results per entity type (default: 5)
#   --project <id>  Scope to a project
#   --json          Emit combined JSON: {"sessions":[...],"tasks":[...],"notes":[...]}

# Examples:
eits search "auth"
eits search "migration" --type tasks,notes --limit 10
eits search "deploy" --json
```

Default output groups results by entity type with headers and counts. Use `--json` for machine-readable combined output.

---

## notes

```bash
eits notes list [--session <uuid>] [--task <id>] [--project <id>] \
  [--mine] [--starred] [--q <query>|--search <query>] \
  [--all] [--limit <n>] [--full]
# Default: lists only current session's notes when EITS_SESSION_UUID is set
# --all: override to list across all sessions
# --full: dump full body for all notes (default: preview listing)
# Preview listing shows: title + first 100 chars + size + created date

eits notes search <query> [--project <id>] [--starred] [--limit <n>] [--full]

eits notes get <id>

eits notes create --parent-type <session|task|agent|project> --parent-id <id> \
  --body <text> [--title <t>] [--starred]

eits notes update <id> [--body <text>] [--title <t>] \
  [--starred|--unstar] \
  [--parent-type <session|task|agent|project>] [--parent-id <id>]

eits notes add --body <text> [--title <t>] [--starred]
# Auto-attach to current session (requires EITS_SESSION_UUID)
```

`--mine` is mutually exclusive with `--session`.

### --help short-circuit

`eits notes get`, `eits notes search`, and `eits notes update` check for `--help` / `-h` before consuming positional arguments, allowing help to be displayed without providing required parameters. Example:

```bash
eits notes update --help         # Shows usage without requiring <id>
eits notes search --help         # Shows usage without requiring <query>
eits notes get --help            # Shows usage without requiring <id>
```

---

## projects

```bash
eits projects list

eits projects get <id>

eits projects create --name <n> --path <p> [--slug <s>] \
  [--remote <url>] [--git-remote <url>] [--repo-url <url>] [--branch <b>] \
  [--active|--inactive]
```

---

## agents

```bash
eits agents list [--project <id>] [--status <status>] [--limit <n>]

eits agents get <id>

eits agents spawn --instructions <text> | --instructions-file <path> \
  [--interpolate-env] \
  [--model <m>] [--provider <p>] \
  [--project-id <n>] [--project-path <path>] [--worktree <branch>] \
  [--stash-if-dirty] \
  [--effort-level <level>] [--parent-session-id <n>] [--parent-agent-id <n>] \
  [--team-name <name>] [--team-id <id>] [--member-name <alias>] [--agent <name>] \
  [--name <session-name>] [--yolo] [--dry-run]
```

**Instructions**: `--instructions <text>` or `--instructions-file <path>` (required, mutually exclusive). `--instructions-file` reads instructions from a file — useful for large payloads that break shell escaping.

**Env interpolation**: `--interpolate-env` substitutes `$VAR` and `${VAR}` patterns in the instructions using the current process environment before sending to the API. Requires `envsubst` (gettext) or `perl`. Useful when instructions come from a file and need to embed runtime values like `$EITS_SESSION_UUID`.

**Project defaults**: `--project-id` defaults to `$EITS_PROJECT_ID`; `--project-path` defaults to `$PWD`.

**Worktree cleanup**: `--stash-if-dirty` auto-stashes uncommitted changes before worktree creation (instead of failing with dirty_working_tree error).

**Team joining**: `--team-name` (by name) or `--team-id` (by integer ID, mutually exclusive). `--team-id` is resolved to team name via GET /teams/:id.

**Sandbox**: `--yolo` bypasses sandbox restrictions. `--provider codex` defaults `bypass_sandbox` to true (can be overridden with explicit flags if needed).

**Session linking**: `--parent-session-id` accepts integer session ID (preferred) or UUID, linking the spawned agent's session to a parent. Prefer `$EITS_SESSION_ID` (integer) for compatibility.

**Pre-flight validation**: `--dry-run` validates inputs without hitting the spawn endpoint. Validates team exists (if `--team-name` provided), parent session exists (if `--parent-session-id` provided), and instructions file is readable (if `--instructions-file` provided). Prints the fully-resolved curl command that would be sent. Exits 0 on success, 1 on any validation failure.

**Valid models by provider:**

`--provider claude` (default):
- claude-opus-4-7, claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4-5-20250929, claude-haiku-4-5-20251001
- Aliases: opus, opus[1m], sonnet, sonnet[1m], haiku

`--provider codex`:
- gpt-5.4, gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.4-mini, gpt-5.3-codex, gpt-5.2

`--provider gemini`:
- gemini-2.5-pro, gemini-2.5-flash, gemini-2.5-flash-lite

---

## commits

```bash
eits commits list [--session <uuid>] [--agent <uuid>] [--mine] [--all] \
  [--since <hash>] [--limit <n>]
# Default: lists only current session's commits when EITS_SESSION_UUID is set
# --all: override to list across all sessions
# --since <hash>: return only commits newer than the given hash (sprint reconciliation)

eits commits create [--agent <uuid>] --hash <h1> [--hash <h2>] [--message <m>] ...
# --agent defaults to $EITS_AGENT_UUID; falls back to session lookup when unset
# If no --hash provided, uses current HEAD (git rev-parse HEAD)
# If no --message provided, uses git log -1 --format=%s
# Response includes top-level boolean: already_tracked=true when ALL submitted hashes were duplicates
# (easier to check than inspecting array lengths)
```

`--mine`, `--session`, and `--agent` are mutually exclusive.

---

## jobs

```bash
eits jobs list [--project <id>] [--global]

eits jobs get <id>

eits jobs create --name <n> --job-type <type> --schedule-type <type> \
  --schedule-value <val> [--description <d>] [--config <json>] \
  [--enabled] [--project <id>]

eits jobs update <id> [--name <n>] [--description <d>] [--job-type <type>] \
  [--schedule-type <type>] [--schedule-value <val>] [--config <json>] \
  [--enabled|--disabled] [--project <id>]

eits jobs run <id>

eits jobs delete <id>
```

---

## dm

```bash
eits dm list [--session <uuid|id>] [--from <uuid|id>] [--limit <n>] [--since <iso8601>] [--json]
eits dm inbox [--session <uuid|id>] [--from <uuid|id>] [--limit <n>] [--since <iso8601>] [--json]
# List inbound DMs for a session (CLI-side inbox polling)
# inbox is an alias for list
# --from: filter by sender (optional)
# --since: return only messages inserted after ISO8601 timestamp (optional)

eits dm [--from <session_id|uuid>] --to <session_id|uuid> --message <text> [--response-required]
# Send a direct message to an agent session
```

Both `--from` and `--to` accept either an integer session ID or a session UUID. `--from` defaults to `$EITS_SESSION_UUID` or `$EITS_SESSION_ID`.

`--since` filters messages by insertion timestamp (ISO8601 format, e.g., `2026-04-30T12:00:00Z`). Useful for orchestrators polling for new replies without diffing the full inbox.

---

## timer

```bash
eits timer show [<session_id>]                     # Get active timer (404 if none)

eits timer set [<session_id>] --preset <5m|10m|15m|30m|1h>

eits timer set [<session_id>] --delay-ms <N> [--mode once|repeating] [--message <text>]

eits timer cancel [<session_id>]                   # Cancel active timer
```

Session defaults to `self` (`$EITS_SESSION_UUID`) when omitted.

---

## channels

```bash
eits channels list [--project <id>]

eits channels create --name <name> [--project <id>] [--description <text>] \
  [--type <public|private>]

eits channels mine [--session <uuid|id>] [--json]

eits channels send <channel_id> --body <text> [--session <uuid|id>] \
  [--broadcast-team <team_id>]

eits channels messages <channel_id> [--limit|-n <N>] [--since <message_id>] [--before <message_id>]

eits channels join <channel_id> [--session <uuid|id>] [--role <member|admin>]

eits channels leave <channel_id> [--session <uuid|id>]

eits channels members <channel_id> [--json]
```

**Subcommand details:**

- `mine`: List channels the current session is a member of. Defaults to `$EITS_SESSION_UUID`. Returns table format (ID, NAME, ROLE, TYPE) or `--json` for raw output.
- `messages`: Get messages from a channel. Default limit is 20, max 200. Use `--since <message_id>` for forward pagination (catch-up), or `--before <message_id>` for backward pagination (load-older).
- `send`: Post a message. `--broadcast-team` fans out a follow-up DM to all team members after posting the channel message.

**Environment injection**: When spawned agents are launched from a channel context (e.g., via Claude provider or Codex with channel binding), `EITS_CHANNEL_ID` is automatically injected into the spawned process environment.

---

## prompts

```bash
eits prompts list [--query|-q <q>] [--project <id>]

eits prompts get <id> [--project <id>] [--no-text]

eits prompts create --name <n> --slug <s> --prompt-text <t> \
  [--description <d>] [--project <id>] [--tags <json>] [--created-by <name>]
```

---

## notifications

```bash
eits notifications create --title <t> [--body <b>] \
  [--category <agent|job|system>] [--resource-type <type>] [--resource-id <id>]
```

---

## teams

```bash
eits teams list [--project <id>] [--status <active|inactive|all>] [--limit <n>]

eits teams get <id>

eits teams create --name <n> [--description <d>] [--project <id>]

eits teams update <id> [--name <name>] [--description <desc>]

eits teams delete <id>

eits teams members <id>

eits teams join <team_id> --name <alias> [--role <member|admin>] \
  [--session <uuid|id>] [--agent <uuid>]

eits teams status <id> [--wait] [--json]
# Default: formatted summary with member status, session state, and current task
# --wait: block until all members reach done or spawn_failed (polls every 5s)
# --json / --raw: output raw JSON instead of formatted text (useful for scripting)

eits teams update-member <team_id> <member_id> --status <s>

eits teams done-self <team_id>                 # Mark current session as done in team

eits teams leave <team_id> <member_id>

eits teams broadcast <team_id> --body <text> [--from <session_id|uuid>]

eits teams my-teams                            # List teams where current agent is a member
```

**`teams list` filters**:
- `--status <active|inactive|all>`: Filter by team status. Default excludes archived teams. Use `all` to include archived.
- `--limit <n>`: Max teams to return (default: all). Negative values are ignored and return all teams.

`teams broadcast` accepts `--message` as an alias for `--body` (for backward compatibility).

`teams status --summary` prints a concise human-readable status showing member counts by state (working, idle, done, failed, spawn_failed).

`--wait` blocks until all members reach a terminal state (done or spawn_failed), polling every 5 seconds. Exits 0 on success, 1 if any spawn_failed.

### Status Fields Explained

Each team member has two status fields:

| Field | Description | Authoritative for |
|-------|-------------|-------------------|
| `member_status` | Team membership state: `active`, `done`, `spawn_failed`, `idle` | Orchestrators checking work completion |
| `session_status` | Claude process lifecycle: `working`, `idle`, `waiting`, `completed`, `failed` | Monitoring Claude Code process state |
| `session_uuid` | UUID of the agent's session (use with `eits dm --to`) | DM targeting |
| `session_id` | Numeric session ID (alternative for `eits dm --to`) | DM targeting |

**Orchestrators should check `member_status`** to know if an agent has finished its work. `session_status` reflects the Claude Code process and can lag behind — an agent that calls `eits tasks complete` will have `member_status: done` immediately, but `session_status` may still show `working` until the session ends.

**`spawn_failed`** in `member_status` means the spawn API returned an error for that team member slot. The member record exists with no linked session or agent.

**DM targeting**: Use `session_uuid` or `session_id` from `teams status` output to send messages: `eits dm --to <uuid|id> --message "..."`. Both UUID and numeric ID are accepted by `dm --to`.

**Default status output** includes:
- Member name and status (active, done, spawn_failed, idle)
- Session status (working, idle, waiting, completed, failed)
- Current claimed task (if any) with title and ID

---

## me

```bash
eits me
eits whoami
```

Prints current session UUID, session ID, agent UUID, project ID, and API URL. If session exists on server, fetches and displays server-side session state.

---

## worktree

```bash
eits worktree create <branch> [--project-path <path>]
eits worktree remove <branch> [--project-path <path>]
```

**Note**: Scoped to EITS Elixir projects (.claude/worktrees/ layout, mix compile verification).

---

## Hooks & Server Availability

EITS hooks (stored in `priv/scripts/` and `.claude/hooks/`) use a shared TCP probe guard (`eits-lib.sh`) to verify the server is available before making API calls. If the server is down, the hook silently exits (exit 0) instead of hanging or erroring.

Each hook sources `eits-lib.sh` after the `EITS_WORKFLOW` guard:

```bash
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"
```

The guard probes TCP to the host/port extracted from `$EITS_URL` (default: `http://localhost:5001/api/v1`). On localhost, the probe completes in sub-millisecond time with no measurable overhead.

The `.claude/hooks/eits-task-gate.sh` hook (stored outside `priv/scripts/`) uses an inlined 2-line version for portability.

---

## Help

```bash
eits help
eits <command> --help
eits <command> <subcommand> --help
```

All subcommands support `--help` / `-h`.

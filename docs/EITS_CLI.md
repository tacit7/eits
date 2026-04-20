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
export EITS_SESSION_ID=<session-id>          # numeric session ID (fallback for --to/--from)
export EITS_AGENT_UUID=<agent-uuid>
export EITS_PROJECT_ID=<project-id>
```

Requires `curl` and `jq`.

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

---

## sessions

```bash
eits sessions list [--search <q>] [--name <partial>] [--status <s>] \
  [--project <id>] [--agent <uuid>] [--mine] \
  [--limit <n>] [--include-archived] [--with-tasks]

eits sessions get <uuid>
eits sessions get self                         # Use current $EITS_SESSION_UUID

eits sessions create --session-id <uuid> [--name <n>] [--description <d>] \
  [--project <name>] [--model <m>] [--entrypoint <e>]

eits sessions update <uuid> [--status <s>] [--intent <text>] \
  [--entrypoint <e>] [--name <name>] [--description <desc>] \
  [--clear-entrypoint] [--ended-at <ISO8601>]

eits sessions end <uuid> [--final-status <completed|failed|waiting>]

eits sessions context <uuid> [--text <text>|--from-stdin] [--metadata <json>]

eits sessions tasks <uuid>     # List tasks linked to session
eits sessions notes <uuid>     # List notes attached to session
```

`--status` filters by session status: `working`, `stopped`, `waiting`, `completed`, `failed`.

`--mine` is mutually exclusive with `--agent`, `--search`, `--status`, `--project`.

`sessions get <uuid>` returns a rich response that includes the session, linked tasks, notes (last 5, body truncated), and commits (last 5) in a single call.

---

## tasks

```bash
# List / filter
eits tasks list [--project <id>] [--session <uuid>] [--q <query>|--search <query>] \
  [--state <id>] [--state-name <todo|in-progress|done|in-review>] \
  [--agent <uuid>] [--mine] [--limit <n>]

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

# Update
eits tasks update <id> [--state <id>|--state-name <done|start|in-progress|in-review|todo>] \
  [--priority <p>] [--title <t>] [--description <d>] [--due-at <ISO8601>]

# State shorthands
eits tasks start <id>          # → In Progress (state 2), auto-links session
eits tasks claim <id>          # Alias for start; auto-links session
eits tasks done <id>           # → Done (state 3)

# Complete with message
eits tasks complete <id> <message>
eits tasks complete <id> --message <text>

# Delete
eits tasks delete <id>

# Annotations
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
```

### Workflow states

| ID | Name        |
|----|-------------|
| 1  | To Do       |
| 2  | In Progress |
| 4  | In Review   |
| 3  | Done        |

### Agent task workflow (canonical)

```bash
# Pick up work (create + start in one shot)
eits tasks begin --title "Implement X"

# Or start existing task
eits tasks claim 42

# Move to review when ready
eits tasks update 42 --state-name in-review

# Complete with summary
eits tasks complete 42 "Implemented via migration + controller change"
```

---

## notes

```bash
eits notes list [--q <query>|--search <query>] [--session <uuid>] \
  [--mine] [--limit <n>]

eits notes search <query>

eits notes get <id>

eits notes create --parent-type <session|task|agent> --parent-id <id> \
  --body <text> [--title <t>] [--starred]

eits notes update <id> [--body <text>] [--title <t>] [--starred]

eits notes add --body <text> [--title <t>]    # Auto-attach to current session
```

`--mine` is mutually exclusive with `--session`.

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

eits agents spawn --instructions <text> [--model <m>] [--provider <p>] \
  [--project-id <n>] [--project-path <path>] [--worktree <branch>] \
  [--effort-level <level>] [--parent-session-id <n>] [--parent-agent-id <n>] \
  [--team-name <name>] [--member-name <alias>] [--agent <name>] \
  [--name <session-name>] [--yolo]
```

`--parent-session-id` accepts integer session ID or UUID, linking the spawned agent's session to a parent.

`--yolo` bypasses sandbox restrictions.

---

## commits

```bash
eits commits list [--session <uuid>] [--agent <uuid>] [--mine] [--limit <n>]

eits commits create [--agent <uuid>] --hash <h1> [--hash <h2>] [--message <m>] ...
# --agent defaults to $EITS_AGENT_UUID
# If no --hash provided, uses current HEAD (git rev-parse HEAD)
# If no --message provided, uses git log -1 --format=%s
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
eits dm [--from <session_id|uuid>] --to <session_id|uuid> --message <text> [--response-required]
```

Both `--from` and `--to` accept either an integer session ID or a session UUID. `--from` defaults to `$EITS_SESSION_UUID` or `$EITS_SESSION_ID`.

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

eits channels send <channel_id> --body <text> [--session <uuid|id>] \
  [--broadcast-team <team_id>]

eits channels messages <channel_id> [--limit|-n <N>]    # Default 20, max 200

eits channels join <channel_id> [--session <uuid|id>] [--role <member|admin>]

eits channels leave <channel_id> [--session <uuid|id>]
```

`--broadcast-team` fans out a follow-up DM to all team members after posting the channel message.

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
eits teams list [--project <id>] [--status <s>]

eits teams get <id>

eits teams create --name <n> [--description <d>] [--project <id>]

eits teams update <id> [--name <name>] [--description <desc>]

eits teams delete <id>

eits teams members <id>

eits teams join <team_id> --name <alias> [--role <member|admin>] \
  [--session <uuid|id>] [--agent <uuid>]

eits teams status <id> [--summary|-s]          # --summary prints human-readable summary

eits teams update-member <team_id> <member_id> --status <s>

eits teams done-self <team_id>                 # Mark current session as done in team

eits teams leave <team_id> <member_id>

eits teams broadcast <team_id> --body <text> [--from <session_id|uuid>]

eits teams my-teams                            # List teams where current agent is a member
```

`teams status --summary` prints a concise human-readable status showing member counts by state (working, idle, done, failed).

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

## Help

```bash
eits help
eits <command> --help
eits <command> <subcommand> --help
```

All subcommands support `--help` / `-h`.

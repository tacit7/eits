---
name: eits-cli
description: Use when an agent needs the correct eits CLI command syntax, flags, or dispatch mode. Triggers on: "how do I use eits", "what's the eits command for", "eits CLI reference", sessions/tasks/notes/commits/agents/jobs/timer/channels/teams/prompts/notifications flags, dispatch mode confusion (cli vs sdk-cli), EITS_URL setup, or any eits subcommand question.
user-invocable: true
allowed-tools: Bash
---

# EITS CLI Reference

The `eits` bash script is the sole interface to the EITS REST API. All agents — interactive (`cli`) and spawned (`sdk-cli`) — use it directly. EITS-CMD directives are **deprecated**.

## Required Environment

```bash
export EITS_URL=http://localhost:5001/api/v1
```

Set this before any `eits` command or you'll get exit 7.

---

## Task Lifecycle

```bash
# Preferred: create + link + start in one shot
eits tasks begin --title "Task name"

# OR: create first, then claim
eits tasks create --title "..." [--description "..."] [--project-id <id>]
eits tasks claim <id>

# Work...

# Finish (PREFERRED — atomic annotate + done in one call)
eits tasks complete <id> --message "Summary"

# Finish (manual two-step — avoid unless complete fails)
eits tasks annotate <id> --body "What happened"
eits tasks update <id> --state done

# Other
eits tasks start <id>              # set state=2, link session (use on EXISTING tasks)
eits tasks list [--all]            # WARNING: scopes to current session when EITS_SESSION_UUID is set; --all overrides
eits tasks list [-p <project>] [-s <session>] [-l <limit>] [--mine]
eits tasks get <id>
```

### Workflow States
| ID | Name        |
|----|-------------|
| 1  | To Do       |
| 2  | In Progress |
| 4  | In Review   |
| 3  | Done        |

---

## Sessions

```bash
eits sessions list [--project-id <id>] [--status <status>] [--include-archived] [--limit <n>]
eits sessions get <uuid>
eits sessions update <uuid> [--status <s>] [--ended-at <iso8601>]
```

---

## Commits

```bash
eits commits create --hash <sha> [--hash <sha2> ...]
eits commits list [--session-id <uuid>] [--project-id <id>]
```

---

## DMs

```bash
# Send
eits dm --to <session_uuid_or_integer_id> --message "text"

# Inbox (inbound DMs, no browser required)
eits dm inbox [--session <uuid|id>] [--limit <n>] [--from <id>] [--since <iso8601>] [--since-session] [--team-only] [--json]
# Key flags:
#   --since-session  only messages since this session started — suppresses stale resume DMs
#   --from <id>      filter by sender UUID or integer ID
#   --team-only      only DMs from sessions sharing a team with you
# alias: eits dm list (identical)
```

`--to` / `--from` accept both UUID and integer session ID.

---

## Notes

```bash
# Create (two forms)
eits notes add --body "..." [--title "t"] [--starred]                          # attaches to current session via EITS_SESSION_UUID
eits notes create --parent-type <session|task|agent|project> --parent-id <id> \
  --body "..." [--title "t"] [--starred]                                       # explicit parent

# List — uses --session/--task/--project (NOT --parent-type/--parent-id)
eits notes list [--session <uuid>] [--task <id>] [--project <id>] [--mine] [--starred] [--q <query>] [--full]

# Search across notes (returns body content)
eits notes search <query> [--project <id>] [--starred] [--limit <n>] [--full]

# Get / update
eits notes get <id>
eits notes update <id> [--body "..."] [--title "t"] [--starred]
```

---

## Agents

```bash
eits agents list [--project-id <id>]
eits agents get <uuid>
eits agents spawn --instructions "..." [options]
  --instructions-file <path>   read instructions from file (mutually exclusive with --instructions)
  --interpolate-env            substitute $VAR/${VAR} in instructions from current env at spawn time
  --name <n>                   session name (NOT --session-name)
  --team-name <name>           join team on spawn (mutually exclusive with --team-id)
  --team-id <id>               join team by ID (resolved to name via API)
  --worktree <branch>          create git worktree branch for the agent
  --stash-if-dirty             auto-stash uncommitted changes before worktree create
  --model <m>                  model shorthand: opus, sonnet, haiku; or codex/gemini models
  --provider <p>               claude (default), codex, gemini
  --parent-session-id <n>      session ID to link as parent — integer ($EITS_SESSION_ID) preferred, UUID also accepted
  --dry-run                    validate + print curl without hitting API
eits agents update <uuid> [--status <s>]
```

`--team-name` and `--team-id` are mutually exclusive. `--interpolate-env` is the clean way to pass orchestrator context (UUID, session ID) into spawned agent instructions without string interpolation hacks — set the vars in your shell, reference them as `$VAR` in the instructions string, pass `--interpolate-env`.

**Spawn output includes a compact summary as the final line** — `session_id`, `session_uuid`, `agent_id`, `worktree_path`, `branch_name`. Extract with:
```bash
session_uuid=$(eits agents spawn ... | tail -1 | jq -r '.session_uuid')
```

---

## Teams

```bash
eits teams list
eits teams get <id>
eits teams create --name "..." [--project-id <id>]
eits teams join <id>
eits teams leave <id>
eits teams done
eits teams status <id> [--wait] [--watch [<n>]] [--json]
# --wait   blocks until all members done/spawn_failed; exits 0/1; prints tick summary every 5s
#          Bare invocation prints a reminder hint about --wait.
# --watch  continuous auto-refresh every N seconds (default 5); Ctrl+C to stop
eits teams update-member <team_id> [--status <s>]
```

---

## Channels

```bash
eits channels list [--project <id>]
eits channels send <channel_id> --body <text> [--session <uuid|id>]   # channel_id is positional integer; --session defaults to $EITS_SESSION_UUID — omit it
eits channels messages <channel_id> [--limit <n>]
eits channels join <channel_id>
eits channels leave <channel_id>
```

---

## Jobs

```bash
eits jobs list [--queue <name>] [--state <s>]
eits jobs get <id>
eits jobs cancel <id>
```

---

## Timer

```bash
eits timer start --task-id <id>
eits timer stop
eits timer status
eits timer list [--task-id <id>]
```

---

## Prompts

```bash
eits prompts list [--project-id <id>] [--query <text>]
eits prompts get <id_or_slug> [--project-id <id>]
eits prompts create --name "..." --slug "..." --prompt-text "..."
```

---

## Projects

```bash
eits projects list
eits projects get <id>
eits projects create --name "..." [--git-remote <url>] [--repo-url <url>] [--branch <b>]
eits projects update <id> [--name <n>] [--active] [--inactive]
```

---

## Notifications

```bash
eits notifications list [--session-id <uuid>] [--unread]
eits notifications mark-read <id>
eits notifications mark-all-read
```

---

## Known Gotchas

1. **`eits agents spawn` exits 7** — `EITS_URL` not set. Always export it first.
2. **Orchestrator pre-created task ID** — use `eits tasks begin --id <task_id>` to claim an existing task atomically (links session + sets In Progress, no duplicate created). Without `--id`, `begin` always creates a new task.
3. **Spawned agents need `--project-id` explicitly** — `EITS_PROJECT_ID` is not auto-injected into child processes.
4. **`dm --to` accepts both UUID and integer** — `$EITS_SESSION_ID` is integer; `$EITS_SESSION_UUID` is UUID. Either works.
5. **Write hook blocks if no active task** — run `eits tasks begin` before editing files.
6. **Agents commit to wrong branch** — always verify `git branch` before committing in a spawned agent.
7. **`tasks begin` has no 429 auto-retry** — unlike `tasks annotate`, `begin` fails hard on rate limit. Retry manually with backoff if you hit 429.
8. **DM to inactive session returns HTTP 422** — sessions in `waiting`, `completed`, or `failed` states are not reachable. The controller now returns 422 (not 500). If the target is unreachable, wait for it to resume or use `eits teams status --wait` instead of DM-based completion polling.
9. **`EITS_AGENT_UUID` unset on resume** — if the resume hook didn't export it, `commits create` auto-resolves the agent UUID from `EITS_SESSION_UUID` via the sessions API. Any other command that needs it can do the same: `EITS_AGENT_UUID=$(eits sessions get $EITS_SESSION_UUID | jq -r '.agent_id')`
10. **`commits create` has no top-level `success` field** — response shape is `{errors, commits, duplicates}`. Check `duplicates | length > 0` for duplicate detection, not a `success` boolean. Example: `echo "$result" | jq '.duplicates | length > 0'`
11. **`--interpolate-env` is the clean env passthrough** — to pass orchestrator UUID to spawned agents without string interpolation: set the var in your shell (`export ORCHESTRATOR_UUID=$EITS_SESSION_UUID`), reference it in the instructions string as `$ORCHESTRATOR_UUID`, pass `--interpolate-env`. No hardcoding, no bash substitution hacks.

---

## Environment Variables

| Variable              | Value / Purpose                          |
|-----------------------|------------------------------------------|
| `EITS_URL`            | `http://localhost:5001/api/v1` (required)|
| `EITS_SESSION_UUID`   | Current session UUID                     |
| `EITS_SESSION_ID`     | Current session integer ID               |
| `EITS_AGENT_UUID`     | Current agent UUID                       |
| `EITS_PROJECT_ID`     | Current project integer ID               |

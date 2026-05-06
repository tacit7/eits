# EITS CLI — Full Command Reference

## Tasks

```bash
eits tasks begin --title "..." [--description "..."] [-p <project_id>] [--tag <id|name>] [--priority <p>]
eits tasks claim <id>          # canonical: transfer ownership to current session, set In Progress
eits tasks begin --id <id>     # compatibility alias for claim; --title/--description silently ignored; --tag still applies
eits tasks start <id>          # DEPRECATED — prints a warning; use claim instead
eits tasks complete <id> --message "Summary" [--commit <sha>] [--commit <sha2> ...]
eits tasks annotate <id> --body "..."
eits tasks update <id> [--state <alias|id>] [--title "..."] [--description "..."] [--priority <p>] [--due-at <iso8601>]
eits tasks list [--all] [-p <project>] [-s <session>] [-l <limit>] [--tag <id|name>] [-q <query>] [--mine]
eits tasks get <id>
eits tasks create --title "..." [--description "..."] [-p <project_id>]
eits tasks active [--json]     # requires session context; visibility helper: In Progress + In Review tasks for current session
# Use --json when you need task IDs for follow-up. Note: In Review does not satisfy the write hook.
eits tasks bulk-update --ids <id,...> [--state <alias|id>] [--priority <p>] [--title "..."]
eits tasks bulk-update --session <uuid|int> [--state <alias|id>] [--priority <p>] [--title "..."]
eits tasks search <query> [-p <project>] [-l <limit>] [--state <id>]
eits tasks states              # list all state IDs and accepted aliases
```

Use `tasks begin` when starting new work immediately — it creates, links, and starts in one shot. Use `tasks create` when creating a task without starting it (write hook still blocks until you `claim` or `begin --id` the task).

Use `tasks claim <id>` for pre-existing or orchestrator-assigned tasks. It transfers ownership to the current session and sets state to In Progress. `tasks update <id> --state start` changes state only — it does not transfer session ownership.

**`--tag` accepts a name or numeric ID.** Non-numeric values are resolved via `/tags?q=<name>` automatically.

**`--mine` filters to the current session** — uses `EITS_SESSION_UUID` or `EITS_SESSION_ID`. Requires at least one to be set.

**`--state` takes positional numbers (1–4) or aliases — not raw DB IDs.**

| Pos | Name        | Aliases                              |
|-----|-------------|--------------------------------------|
| 1   | To Do       | `todo`, `to-do`, `to do`             |
| 2   | In Progress | `start`, `in-progress`, `progress`   |
| 3   | In Review   | `review`, `in-review`                |
| 4   | Done        | `done`, `complete`, `completed`      |

Run `eits tasks states` for the full authoritative list.

---

## Sessions

```bash
eits sessions list [-p <project_id>] [--status <s>] [--include-archived] [--limit <n>]
eits sessions get <uuid>

# Agents updating their own session — use 'self', no UUID needed
eits sessions update self [--status <s>] [--name "..."] [--description "..."] [--project-id <id>] [--ended-at <iso8601>]
eits sessions set-intent <review|work>      # defaults to $EITS_SESSION_UUID when uuid omitted

eits sessions end <uuid> [--final-status <completed|failed|waiting>]
eits sessions complete [<uuid>]             # defaults to $EITS_SESSION_UUID; prefer over sessions end for self
eits sessions waiting [<uuid>]              # defaults to $EITS_SESSION_UUID; prefer over sessions end for self
eits sessions tasks <uuid>
eits sessions notes <uuid>
```

Some session commands support `self` or omitted UUIDs and resolve to `$EITS_SESSION_UUID` automatically. Do not assume `self` works everywhere — `sessions get self` has a server-side bug (CastError). Use `eits sessions get $EITS_SESSION_UUID` explicitly.

---

## Commits

```bash
eits commits create --hash <sha> [--hash <sha2> ...]
eits commits list [--session <uuid>] [--mine] [--all] [--limit <n>]
```

Response shape is `{errors, commits, duplicates}` — no top-level `success`. Check duplicates with `jq '.duplicates | length > 0'`. Treat `commits create` as successful when it exits 0 and `.errors` is empty. Duplicate hashes in `.duplicates` are informational, not fatal.

---

## DMs

```bash
# Send
eits dm --to <session_uuid_or_integer_id> --message "text"

# Inbox — auto-resolves from $EITS_SESSION_UUID; omit --session
eits dm inbox [--limit <n>] [--from <id>] [--since <iso8601>] [--since-session] [--team-only] [--json]
# --session <uuid|id> is an override only — don't pass it when reading your own inbox
# alias: eits dm list
```

`--to` / `--from` accept UUID or integer session ID.
`--since-session` suppresses stale DMs from before session start — use this on resume.
`--unread` does **not** exist (no is_read field in the backend).

---

## Notes

```bash
# Create
eits notes add --body "..." [--title "t"] [--starred]                               # attaches to current session
eits notes create --parent-type <session|task|agent|project> --parent-id <id> \
  --body "..." [--title "t"] [--starred]                                            # explicit parent
# Use notes add for quick session notes; use notes create when attaching to a task, agent, or project.

# List (uses --session/--task/--project, NOT --parent-type/--parent-id)
eits notes list [--session <uuid>] [--task <id>] [--project <id>] [--mine] [--starred] [--q <query>] [--full]

# Search, get, update
eits notes search <query> [--project <id>] [--starred] [--limit <n>] [--full]
eits notes get <id>
eits notes update <id> [--body "..."] [--title "t"] [--starred]
```

---

## Agents

```bash
eits agents list [-p <project_id>]
eits agents get <uuid>
eits agents defs [--json]       # list agent definitions (descriptions truncated to 500 chars; use --json for full)
eits agents update <uuid|id> [--status <s>] [--status-message "text"]
# at least one flag required; agents updating themselves: eits agents update $EITS_AGENT_UUID --status-message "working on X"
# known --status values: working, idle, waiting, completed, failed (passed through to server; not validated by CLI)
eits agents spawn --instructions "..." [options]
  --instructions-file <path>   read from file (avoids shell escaping issues with heredocs/sigils)
  --interpolate-env            expand $VAR in instructions from current env at spawn time
  --agent <name>               agent definition name (slug) to spawn
  --name <n>                   session name
  --team-name <name>           join team on spawn (mutually exclusive with --team-id)
  --team-id <id>               join team by ID (resolved to name; warns + continues if not found)
  --worktree <branch>          create git worktree branch
  --stash-if-dirty             auto-stash before worktree create
  --model <m>                  opus / sonnet / haiku or provider-specific model name
  --provider <p>               claude (default) | codex | gemini
  --project-id <id>            project context for spawned session (default: $EITS_PROJECT_ID)
  --parent-session-id <n>      integer preferred ($EITS_SESSION_ID); UUID also accepted
  --dry-run                    validate + print curl without hitting API; use before complex spawns
```

**Spawn output** — last line is a compact JSON summary. Extract:
```bash
session_uuid=$(eits agents spawn ... | tail -1 | jq -r '.session_uuid')
```

**`--interpolate-env`** is the clean way to pass orchestrator context into spawned instructions. Set vars in your shell, reference as `$VAR` in the instructions string, pass the flag.

---

## Teams

```bash
eits teams list [--project <id>] [--status <active|inactive|all>] [--limit <n>]
eits teams get <id|name>
eits teams create --name "..." [--description "..."] [--project <id>]
eits teams delete <id>         # destructive: removes team and all membership records
eits teams update <id> [--name "..."] [--description "..."]
eits teams members <id>
eits teams join <team_id> --name <alias> [--role member|admin] [--session <uuid|id>] [--agent <uuid>]
eits teams leave <team_id> <member_id>   # member_id is required; removes that member from the team
eits teams done                          # mark yourself done in all joined teams
eits teams update-member <team_id> [--status <s>]
eits teams status <id> [--wait] [--watch [<n>]] [--json]
  # --wait   blocks until all members done/spawn_failed; exits 0 on all-done, 1 otherwise
  # --watch  continuous refresh every N seconds (default 5)
  # Use --wait for completion detection. Do not DM-poll sessions to infer completion.
eits teams broadcast <team_id> --body "text" [--from <session_uuid|id>]   # --from defaults to $EITS_SESSION_UUID
eits teams my-teams [--json]
```

`teams create` response includes `id`, `uuid`, and `name`.

---

## Channels

```bash
eits channels list [--project <id>]
eits channels send <channel_id> --body "text" [--broadcast-team <team_id>]
# --broadcast-team fans out DMs to all team members after posting; use intentionally
eits channels messages <channel_id> [--limit <n>]
eits channels join <channel_id>
eits channels leave <channel_id>
```

---

## Jobs

```bash
eits jobs list [--queue <name>] [--state <s>]   # job states are backend-defined; inspect with jobs list before filtering
eits jobs get <id>
eits jobs cancel <id>          # high-impact: cancels a running background job
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
eits prompts list [-p <project_id>] [--query <text>]
eits prompts get <id_or_slug> [--project <id>]
eits prompts create --name "..." --slug "..." --prompt-text "..." [--project <id>]
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

## Tags

```bash
eits tags list [--q <query>]
eits tags get <id>
```

---

## Notifications

```bash
eits notifications create --title "..." [--body "..."] [--category agent|job|system] \
  [--resource-type <type>] [--resource-id <id>]    # high-impact: emits a notification
```

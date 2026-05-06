# EITS CLI — Full Command Reference

## Tasks

```bash
eits tasks begin --title "..." [--id <existing_task_id>] [--description "..."] [--project-id <id>] [--tag <id|name>]
eits tasks complete <id> --message "Summary"
eits tasks annotate <id> --body "..."
eits tasks update <id> --state <alias|id> [--title "..."] [--description "..."]
eits tasks list [--all] [-p <project>] [-s <session>] [-l <limit>] [--tag <id|name>] [-q <query>] [--mine]
eits tasks get <id>
eits tasks create --title "..." [--description "..."] [--project-id <id>]
eits tasks claim <id>
eits tasks start <id>          # set state=2 + link session (use on pre-existing tasks, NOT begin)
eits tasks active [--json]     # In Progress + In Review tasks linked to current session
eits tasks bulk-update --ids <id,...> --state <alias|id>
eits tasks search <query> [-p <project>] [-l <limit>] [--state <id>]
eits tasks states              # list all state IDs and accepted aliases
```

**`--tag` accepts a name or numeric ID.** Non-numeric values are resolved via `/tags?q=<name>` automatically.

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
eits sessions list [--project-id <id>] [--status <s>] [--include-archived] [--limit <n>]
eits sessions get <uuid>
eits sessions update <uuid|self> [--status <s>] [--name "..."] [--description "..."] [--project-id <id>] [--ended-at <iso8601>]
eits sessions set-intent <review|work> [<uuid>]
eits sessions end <uuid> [--final-status <completed|failed|waiting>]
eits sessions complete [<uuid>]
eits sessions waiting [<uuid>]
eits sessions tasks <uuid>
eits sessions notes <uuid>
```

`self` resolves to `$EITS_SESSION_UUID` where supported.

---

## Commits

```bash
eits commits create --hash <sha> [--hash <sha2> ...]
eits commits list [--session-id <uuid>] [--project-id <id>]
```

Response shape is `{errors, commits, duplicates}` — no top-level `success`. Check duplicates with `jq '.duplicates | length > 0'`.

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
eits agents list [--project-id <id>]
eits agents get <uuid>
eits agents defs [--json]       # list agent definitions (descriptions truncated to 500 chars; use --json for full)
eits agents update <uuid> [--status <s>]
eits agents spawn --instructions "..." [options]
  --instructions-file <path>   read from file (avoids shell escaping issues with heredocs/sigils)
  --interpolate-env            expand $VAR in instructions from current env at spawn time
  --name <n>                   session name
  --team-name <name>           join team on spawn (mutually exclusive with --team-id)
  --team-id <id>               join team by ID (resolved to name; warns + continues if not found)
  --worktree <branch>          create git worktree branch
  --stash-if-dirty             auto-stash before worktree create
  --model <m>                  opus / sonnet / haiku or provider-specific model name
  --provider <p>               claude (default) | codex | gemini
  --parent-session-id <n>      integer preferred ($EITS_SESSION_ID); UUID also accepted
  --dry-run                    validate + print curl without hitting API
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
eits teams delete <id>
eits teams update <id> [--name "..."] [--description "..."]
eits teams members <id>
eits teams join <team_id> --name <alias> [--role member|admin] [--session <uuid|id>] [--agent <uuid>]
eits teams leave <team_id> [<member_id>]
eits teams done                          # mark yourself done in all joined teams
eits teams update-member <team_id> [--status <s>]
eits teams status <id> [--wait] [--watch [<n>]] [--json]
  # --wait   blocks until all members done/spawn_failed; exits 0 on all-done, 1 otherwise
  # --watch  continuous refresh every N seconds (default 5)
eits teams broadcast <team_id> --from-session-id <id> --body "text"
eits teams my-teams [--json]
```

`teams create` response includes `id`, `uuid`, and `name`.

---

## Channels

```bash
eits channels list [--project <id>]
eits channels send <channel_id> --body "text"    # --session defaults to $EITS_SESSION_UUID; omit it
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

## Tags

```bash
eits tags list [--q <query>]
eits tags get <id>
```

---

## Notifications

```bash
eits notifications list [--session-id <uuid>] [--unread]
eits notifications mark-read <id>
eits notifications mark-all-read
```

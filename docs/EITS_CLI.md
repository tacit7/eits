# eits CLI

Bash script at `scripts/eits`. Talks to the Eye in the Sky REST API.

## Setup

```bash
# Default URL
export EITS_URL=http://localhost:5000/api/v1

# Optional auth
export EITS_API_KEY=<your-key>

# Injected automatically by EITS hooks — set manually if needed
export EITS_SESSION_UUID=<session-uuid>
export EITS_AGENT_UUID=<agent-uuid>
export EITS_PROJECT_ID=<project-id>
```

Requires `curl` and `jq`.

---

## sessions

```bash
eits sessions list
eits sessions get <uuid>
eits sessions create --session-id <uuid> [--name <n>] [--description <d>] [--project <name>] [--model <m>] [--entrypoint <e>]
eits sessions update <uuid> [--status <s>] [--intent <text>] [--entrypoint <e>]
eits sessions end <uuid>
eits sessions context <uuid>
```

---

## tasks

```bash
# List / filter
eits tasks list [--project <id>] [--session <uuid>] [--q <query>] [--state <id>] [--limit <n>]

# Get
eits tasks get <id>

# Create
eits tasks create --title <t> [--description <d>] [--project <id>] [--priority <p>] \
  [--session <uuid>] [--agent <uuid>] [--tags <id1,id2,...>]
# Defaults: --agent from $EITS_AGENT_UUID, --project from $EITS_PROJECT_ID, --session from $EITS_SESSION_UUID

# Update
eits tasks update <id> [--state <state_id>] [--state-name <done|start>] \
  [--priority <p>] [--description <d>] \
  [--assignee <agent-uuid>]    # assign to a specific agent
  [--assignee-self]            # assign to $EITS_AGENT_UUID

# State shorthands
eits tasks start <id>     # → In Progress (state 2), links current session
eits tasks done <id>      # → Done (state 3)

# Delete
eits tasks delete <id>

# One-shot: create + start + link session
eits tasks quick --title <t> [--description <d>] [--project <id>] [--priority <p>]

# Annotations
eits tasks annotate <id> --body <text> [--title <t>]

# Session linking
eits tasks link-session <task_id> [<session_uuid>]     # defaults to $EITS_SESSION_UUID
eits tasks unlink-session <task_id> <session_uuid>

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
# Pick up work
eits tasks start 42                   # links session, sets In Progress

# Or create-and-start in one shot
eits tasks quick --title "Implement X"

# Assign to self
eits tasks update 42 --assignee-self

# Move to review
eits tasks update 42 --state 4

# Annotate before closing
eits tasks annotate 42 --body "Implemented via migration + controller change"
```

---

## notes

```bash
eits notes list [--q <query>] [--session <uuid>] [--limit <n>]
eits notes get <id>
eits notes create --parent-type <session|task|agent> --parent-id <id> --body <text> \
  [--title <t>] [--starred]
eits notes update <id> [--body <text>] [--title <t>] [--starred]
```

---

## projects

```bash
eits projects list
eits projects get <id>
eits projects create --name <n> --path <p> [--slug <s>] [--remote <url>]
```

---

## agents

```bash
eits agents list
eits agents get <id>
eits agents spawn --instructions <text> [--model <m>] [--provider <p>] \
  [--project-id <n>] [--project-path <path>] [--worktree <branch>] \
  [--effort-level <level>] [--parent-session-id <n>] [--parent-agent-id <n>] \
  [--team-name <name>] [--member-name <alias>] [--agent <name>]
```

---

## commits

```bash
eits commits list
eits commits create [--agent <uuid>] --hash <h1> [--hash <h2>] [--message <m>]
# --agent defaults to $EITS_AGENT_UUID
```

---

## jobs

```bash
eits jobs list
eits jobs get <id>
eits jobs run <id>
eits jobs delete <id>
```

---

## dm

```bash
eits dm [--from <sender_id>] --to <target_session_uuid> --message <text> [--response-required]
# --from defaults to $EITS_AGENT_UUID
```

---

## channels

```bash
eits channels list [--project <id>]
eits channels send <channel_id> --session <uuid> --body <text>
```

---

## prompts

```bash
eits prompts list
eits prompts get <id>
```

---

## teams

```bash
eits teams list [--project <id>] [--status <s>]
eits teams get <id>
eits teams create --name <n> [--description <d>] [--project <id>]
eits teams delete <id>
eits teams members <id>
eits teams join <team_id> --name <alias> [--role <r>] [--session <uuid>] [--agent <uuid>]
eits teams status <id>
eits teams update-member <team_id> <member_id> --status <s>
eits teams leave <team_id> <member_id>
```

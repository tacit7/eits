---
name: eits-teams
description: Create and manage EITS agent teams for coordinated multi-agent work. Use this skill whenever the user wants to spawn multiple agents to work together, coordinate parallel tasks, run a swarm, delegate work across agents, or says things like "create a team", "spin up agents to", "have agents work on this together", "coordinate agents", or "run agents in parallel". EITS teams are fully server-owned — membership is tracked in Postgres, not local files.
user-invocable: true
allowed-tools: Bash
---

# EITS Teams

EITS teams coordinate multiple Claude agents in parallel. Membership is server-side — agents auto-join on spawn.

---

## CLI Reference

```bash
eits teams list [--project <id>] [--status <status>]
eits teams get <id|name>
eits teams create --name <name> [--description <desc>] [--project <id>]
eits teams delete <id>
eits teams members <id>
eits teams join <team_id> --name <alias> [--role lead|member] [--session <uuid>]
eits teams status <id>
eits teams update-member <team_id> <member_id> --status <active|idle|done|failed>
eits teams leave <team_id> <member_id>
```

Spawn an agent:

```bash
eits agents spawn \
  --instructions "Your task prompt" \
  --model sonnet \
  --project-path /path/to/repo \
  --worktree feature-branch \
  --effort-level high \
  --parent-session-id <ORC_SESSION_ID> \
  --parent-agent-id <ORC_AGENT_ID> \
  --team-name my-team \
  --member-name researcher
```

Only `--instructions` is required. `--project-id` is inherited from parent session automatically — do not pass it.

---

## Workflow

### 1. Create team

```bash
eits teams create --name "my-team" --description "What this team is doing"
# Returns team_id
```

### 2. Join as orchestrator

Always pass `--session` explicitly — auto-resolve can silently produce NULL and break the DM link in the Teams UI:

```bash
eits teams join <team_id> --name "orchestrator" --role lead --session $EITS_SESSION_UUID
```

### 3. Create shared tasks

```bash
eits tasks create --title "Research X" --description "Details" --team <team_id>
# Create all tasks upfront so agents can claim them
```

### 4. Get orchestrator IDs

Spawning requires **integer** IDs, not UUIDs:

```bash
ORC_SESSION_ID=$(eits sessions get $EITS_SESSION_UUID | jq '.id')
ORC_AGENT_ID=$(psql -d eits_dev -t -c "SELECT a.id FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$EITS_SESSION_UUID'" | tr -d ' ')
```

### 5. Spawn agents

Always include `parent_session_id` and `parent_agent_id` for proper session hierarchy:

```bash
eits agents spawn \
  --instructions "Your task. team_id: <team_id>. When done, DM back: eits dm --to <ORC_SESSION_UUID> --message 'done'" \
  --model sonnet \
  --team-name my-team \
  --member-name researcher \
  --parent-session-id $ORC_SESSION_ID \
  --parent-agent-id $ORC_AGENT_ID
```

**Always embed the orchestrator's UUID literally in instructions** — agents use it to DM back. Use `$EITS_SESSION_UUID` (UUID), never the integer ID.

Spawn all agents in parallel. Each gets a unique `--member-name`.

### 6. Monitor

```bash
eits teams status <team_id>
# Shows members with live session_status (idle/working/completed/failed)
```

Send DMs to check progress — **sequentially, never in parallel Bash calls**:

```bash
eits dm --to $UUID_1 --message "Status update: what is your progress?"
eits dm --to $UUID_2 --message "Status update: what is your progress?"
```

Resolve session UUID from integer ID if needed:

```bash
AGENT_UUID=$(psql -d eits_dev -tAq -c "SELECT uuid FROM sessions WHERE id = <session_id>;")
```

### 7. Review and close out

When an agent DMs that it's done, DM it to complete the task completion sequence:

```bash
eits dm --to <agent_uuid> --message "Work complete. Run the task completion sequence and update your session status."
```

### 8. Shutdown

Leave the team active — **do NOT delete** unless the user explicitly says so.

```bash
eits teams delete <id>   # only when explicitly instructed
```

---

## Agent-Side Behavior

Agents auto-receive team context. They are expected to:

```bash
eits tasks claim <task_id>            # in-progress, self-assign, link session
# ... do work ...
eits tasks complete <task_id> --message "Summary of what was done"
# complete: annotates, marks done, sets team member status → done, DMs lead
```

If `complete` fails, fall back:

```bash
eits tasks annotate <task_id> --body "Summary"
eits tasks update <task_id> --state 4
```

**Stop hook enforces completion** — `.claude/hooks/eits-task-gate.sh` blocks exit if any task is in state 2 linked to the session.

---

## Rules

- **Never manually insert DB records and spawn `claude` directly** — breaks `git_worktree_path`, session hierarchy, and "Load messages".
- **`--to` in `eits dm` requires UUID** — never an integer session ID.
- **DM sequentially** — parallel Bash DM calls cancel siblings on error.
- **Don't pass `--project-id` when `--parent-session-id` is set** — it's inherited.
- `--worktree` requires a clean working tree — commit or stash first.

---

## Example: 2-Agent Research + Write

```bash
# 1. Create team
eits teams create --name "docs-team" --description "Research flags and write README"

# 2. Join as orchestrator
eits teams join <team_id> --name "orchestrator" --role lead --session $EITS_SESSION_UUID

# 3. Create tasks
eits tasks create --title "Research Claude CLI flags" --team <team_id>
eits tasks create --title "Write README from research" --team <team_id>

# 4. Get IDs
ORC_SESSION_ID=$(eits sessions get $EITS_SESSION_UUID | jq '.id')
ORC_AGENT_ID=$(psql -d eits_dev -t -c "SELECT a.id FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$EITS_SESSION_UUID'" | tr -d ' ')

# 5. Spawn agents
eits agents spawn \
  --instructions "Investigate all claude --help flags. Write findings to /tmp/research.md. team_id: <team_id>. DM back to $EITS_SESSION_UUID when done." \
  --model sonnet --team-name docs-team --member-name researcher \
  --parent-session-id $ORC_SESSION_ID --parent-agent-id $ORC_AGENT_ID

eits agents spawn \
  --instructions "Wait for /tmp/research.md, then write docs/README.md. team_id: <team_id>. DM back to $EITS_SESSION_UUID when done." \
  --model sonnet --team-name docs-team --member-name writer \
  --parent-session-id $ORC_SESSION_ID --parent-agent-id $ORC_AGENT_ID

# 6. Monitor
eits teams status <team_id>
eits dm --to $RESEARCHER_UUID --message "Status update?"
eits dm --to $WRITER_UUID --message "Status update?"
```

---

## Tips

- **Pass `team_id` in agent instructions** so they don't have to look it up.
- **Use descriptive `--member-name` values** — DMs identify agents by this alias.
- **Teams LiveView at `/teams`** — real-time member status and per-member task lists.
- **One team per logical unit of work** — don't reuse teams across unrelated tasks.
- **Task must be linked to session** for Stop hook to gate. `eits tasks claim` handles this. Verify: `psql -d eits_dev -c "SELECT task_id FROM task_sessions WHERE session_id = (SELECT id FROM sessions WHERE uuid = '$EITS_SESSION_UUID')"`

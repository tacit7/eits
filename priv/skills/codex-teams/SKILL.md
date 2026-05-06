---
name: codex-teams
description: Create and manage EITS agent teams from a Codex orchestrator. Use when coordinating parallel tasks, spawning multiple agents, or monitoring team status.
---

# Codex EITS Teams

## CLI Reference

```bash
eits teams create --name <name> [--description <desc>]
eits teams join <team_id> --name <alias> --role lead --session $EITS_SESSION_UUID
eits teams status <team_id> [--wait]   # --wait blocks until all members done; exits 0/1
eits teams members <team_id>
eits teams leave <team_id> <member_id>
eits tasks create --title "..." --description "..." --team <team_id>
```

Spawn an agent:
```bash
eits agents spawn \
  --instructions "..." \
  --model sonnet \
  --project-path /path/to/repo \
  --parent-session-id <ORC_SESSION_ID> \
  --parent-agent-id <ORC_AGENT_ID> \
  --team-name my-team \
  --member-name worker-1
```

---

## Workflow

### 1. Create team + join as lead
```bash
eits teams create --name "my-team" --description "..." --project-id $EITS_PROJECT_ID
# ALWAYS pass --project-id — omitting it sets project_id=null and hides the team from /projects/:id/teams
eits teams join <team_id> --name "orchestrator" --role lead --session $EITS_SESSION_UUID
```

### 2. Create shared tasks upfront
```bash
eits tasks create --title "Task A" --team <team_id>
eits tasks create --title "Task B" --team <team_id>
```

### 3. Get orchestrator integer IDs (required for spawn)
```bash
ORC_SESSION_ID=$(eits sessions get $EITS_SESSION_UUID | jq '.id')
ORC_AGENT_ID=$(eits sessions get $EITS_SESSION_UUID | jq '.agent_int_id')
```

### 4. Spawn agents sequentially (preferred — avoids 429 rate limits)
```bash
# Spawn sequentially; capture session_uuid from compact final line
W1=$(eits agents spawn --instructions "..." --team-name my-team --member-name worker-1 \
  --parent-session-id $ORC_SESSION_ID --parent-agent-id $ORC_AGENT_ID | tail -1 | jq -r '.session_uuid')

W2=$(eits agents spawn --instructions "..." --team-name my-team --member-name worker-2 \
  --parent-session-id $ORC_SESSION_ID --parent-agent-id $ORC_AGENT_ID | tail -1 | jq -r '.session_uuid')
```

**Do NOT use `&` + `wait` for parallel spawns** — 4+ concurrent spawns hit rate limits and bail. Spawn sequentially with a short sleep between calls if you hit 429.

Embed `$EITS_SESSION_UUID` or `$EITS_SESSION_ID` in instructions so agents can DM back.

### 5. Monitor
```bash
# Block until all done — preferred over polling loops
eits teams status <team_id> --wait

# Collect results (suppress stale DMs from prior sessions)
eits dm inbox --since-session
```

`waiting` status ≠ stuck — agent session ended and is resumable. `member_status` is authoritative for completion, not `session_status`.

---

## Code Work Pattern (per agent)

Include in agent instructions:
```
1. eits tasks begin --title "<task name>"
2. Read all files before editing
3. Make changes in your worktree only
4. mix compile --warnings-as-errors
5. git commit; eits commits create --hash $(git rev-parse HEAD)
6. Use /pr skill for Codex review. Repeat until LGTM. Merge.
7. eits dm --to <ORC_UUID> --message "done: <PR_URL>"
```

---

## Rules

- `--to` in `eits dm` accepts UUID **or** integer session ID — both work.
- DM sequentially — parallel calls cancel siblings on error.
- Do NOT delete teams unless explicitly told to.
- Don't pass `--project-id` when `--parent-session-id` is set.

---
name: eits-teams
description: Create and manage EITS agent teams from a Codex orchestrator. Use when coordinating parallel tasks, spawning multiple agents, or monitoring team status.
---

# Codex EITS Teams

For Codex sessions, source `~/.eits/codex/sessions/<session_id>.env` in the
same Bash command before using `$EITS_SESSION_UUID`, `$EITS_SESSION_ID`,
`$EITS_AGENT_ID`, or `$EITS_PROJECT_ID` shell expansion. Plain `eits` CLI calls
auto-load the session-specific file only when `EITS_CODEX_SESSION_ID`,
`CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set. If no session id is known, ask
the user for it.

## CLI Reference

```bash
eits teams create --name <name> [--description <desc>]
eits teams join <team_id> --name <alias> --role lead --session $EITS_SESSION_UUID
eits teams status <team_id> [--wait]   # --wait blocks until all members done; exits 0/1
eits teams members <team_id>
eits teams leave <team_id> <member_id>
eits tasks create --title "..." --description "..." --team <team_id>
eits tasks claim <task_id>             # claim an orchestrator-assigned task
```

Spawn an agent:
```bash
eits agents spawn \
  --provider codex \
  --model gpt-5.4-mini \
  --instructions "..." \
  --project-path /path/to/repo \
  --project-id <project_id> \
  --parent-session-id <ORC_SESSION_ID> \
  --parent-agent-id <ORC_AGENT_ID> \
  --team-name my-team \
  --member-name worker-1
```

---

## Workflow

### 1. Create team + join as lead
```bash
eits teams create --name "my-team" --description "..." --project $EITS_PROJECT_ID
# ALWAYS pass --project — omitting it sets project_id=null and hides the team from /projects/:id/teams
# NOTE: teams create uses --project, not --project-id.
eits teams join <team_id> --name "orchestrator" --role lead --session $EITS_SESSION_UUID
```

### 2. Create shared tasks upfront
```bash
eits tasks create --title "Task A" --team <team_id>
eits tasks create --title "Task B" --team <team_id>
```
Create tasks in To Do state for workers to claim. Do not tell workers to run
plain `eits tasks begin --title ...` for pre-created team work; that creates a
duplicate task. Assigned workers must run `eits tasks claim <task_id>` (or the
compatibility alias `eits tasks begin --id <task_id>`).

### 3. Get orchestrator integer IDs (required for spawn)
```bash
ORC_SESSION_ID=$(eits sessions get $EITS_SESSION_UUID | jq '.id')
ORC_AGENT_ID=$(eits sessions get $EITS_SESSION_UUID | jq '.agent_int_id')
```

### 4. Spawn agents sequentially (preferred — avoids 429 rate limits)
```bash
# Spawn sequentially; capture session_uuid from compact final line
W1=$(eits agents spawn --provider codex --model gpt-5.4-mini --project-id $EITS_PROJECT_ID \
  --instructions "Assigned task: 123. Claim it with: eits tasks claim 123. Do not create a duplicate task. DM back to $ORC_SESSION_ID when done." \
  --team-name my-team --member-name worker-1 \
  --parent-session-id $ORC_SESSION_ID --parent-agent-id $ORC_AGENT_ID | tail -1 | jq -r '.session_uuid')

W2=$(eits agents spawn --provider codex --model gpt-5.4-mini --project-id $EITS_PROJECT_ID \
  --instructions "Assigned task: 124. Claim it with: eits tasks claim 124. Do not create a duplicate task. DM back to $ORC_SESSION_ID when done." \
  --team-name my-team --member-name worker-2 \
  --parent-session-id $ORC_SESSION_ID --parent-agent-id $ORC_AGENT_ID | tail -1 | jq -r '.session_uuid')
```

**Do NOT use `&` + `wait` for parallel spawns** — 4+ concurrent spawns hit rate limits and bail. Spawn sequentially with a short sleep between calls if you hit 429.

Embed `$EITS_SESSION_UUID` or `$EITS_SESSION_ID` in instructions so agents can DM back.
Every worker instruction must include:
- assigned task id
- `eits tasks claim <task_id>`
- "Do not create a duplicate task"
- the orchestrator session id to DM on completion
- the expected DM format

### 5. Monitor
```bash
# Block until all done — preferred over polling loops
eits teams status <team_id> --wait

# Collect results (suppress stale DMs from prior sessions)
eits dm inbox --since-session --team-only --json
```

`waiting` status ≠ stuck — agent session ended and is resumable. `member_status` is authoritative for completion, not `session_status`.

---

## Code Work Pattern (per agent)

Include in agent instructions:
```
1. eits tasks claim <assigned_task_id>
2. Do not create a duplicate task. If no task id was assigned, DM the orchestrator and wait.
3. Check `eits dm inbox --since-session --team-only --json` at start/resume.
4. Read all files before editing.
5. Make changes in your worktree only.
6. mix compile --warnings-as-errors
7. git commit; eits commits create --hash $(git rev-parse HEAD)
8. Use the eits-pr skill for Codex review when code changes need review. Repeat until LGTM. Merge.
9. eits tasks complete <assigned_task_id> --message "Summary of what was done"
10. eits dm --to <ORC_SESSION_ID> --message "done task=<id> result=<summary> branch=<branch-or-pr>"
```

---

## Rules

- `--to` in `eits dm` accepts UUID **or** integer session ID — both work.
- DM sequentially — parallel calls cancel siblings on error.
- DM the orchestrator explicitly when done; task completion does not send that DM for you.
- Claim assigned tasks with `eits tasks claim <id>`; plain `eits tasks begin --title ...` creates new work and duplicates pre-created team tickets.
- Check the DM inbox at start/resume and before marking done.
- Do NOT delete teams unless explicitly told to.
- For `teams create`, the project flag is `--project`. For `agents spawn`, use `--project-id` when project context matters.

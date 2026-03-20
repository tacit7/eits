# EITS Team Execution Protocol

How to use EITS teams for parallel agent work within the eits-superpowers workflow.

## When to Use Teams vs Solo

| Criteria | Solo | Team |
|----------|------|------|
| 1-2 independent tasks | X | |
| 3+ independent tasks | | X |
| Tasks need different expertise | | X |
| Tightly coupled, shared state | X | |
| Quick bugfix or small feature | X | |
| Multi-file feature with clear boundaries | | X |

## Team Setup Sequence

### 1. Create the team

```bash
eits teams create --name "<feature>-team" --description "What this team is doing"
```

### 2. Join as orchestrator

```bash
eits teams join <team_id> --name "orchestrator" --role lead --session $EITS_SESSION_UUID
```

### 3. Create tasks for the team

```bash
eits tasks create --title "Task 1: <component>" --description "Details" --team <team_id>
eits tasks create --title "Task 2: <component>" --description "Details" --team <team_id>
```

Create all tasks upfront so agents can claim them.

### 4. Get orchestrator IDs

```bash
ORC_SESSION_ID=$(eits sessions get $EITS_SESSION_UUID | jq '.id')
ORC_AGENT_ID=$(psql -d eits_dev -t -c "SELECT a.id FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$EITS_SESSION_UUID'" | tr -d ' ')
```

### 5. Spawn agents

```bash
eits agents spawn \
  --instructions "Your task prompt. When done: eits tasks complete <id> --message 'summary'. Then DM orchestrator: eits dm --to $EITS_SESSION_UUID --message 'Task #<id> complete.'" \
  --model sonnet \
  --project-path /Users/urielmaldonado/projects/eits/web \
  --team-name "<feature>-team" \
  --member-name "<role>" \
  --parent-session-id $ORC_SESSION_ID \
  --parent-agent-id $ORC_AGENT_ID
```

Key points:
- Always include `--parent-session-id` and `--parent-agent-id`
- Always include the orchestrator's `$EITS_SESSION_UUID` in instructions for DM replies
- Use `--worktree <branch>` for file-editing agents to avoid conflicts
- Do NOT pass `--project-id`; it is inherited from parent

### 6. Monitor

```bash
eits teams status <team_id>
eits dm --to <agent_session_uuid> --message "Status update?"
```

DM agents sequentially, never in parallel Bash calls.

### 7. Review and close

When agents DM back that they are done:
1. Review their work (check commits, run tests)
2. DM each agent to run `/i-update-status`
3. Leave team active unless user says to archive

## Model Selection for Team Members

| Task type | Model | Examples |
|-----------|-------|----------|
| Mechanical, clear spec, 1-2 files | haiku | Add a field, write a migration, simple test |
| Integration, multi-file, judgment | sonnet | LiveView + context + tests, API endpoint |
| Architecture, design, review | opus | System design, code review, debugging |

## Agent Instructions Template

Include in every spawned agent's instructions:

```
You are a member of the "<team-name>" team.

Your task: <specific task description>

Task ID: <task_id>
Team ID: <team_id>

Workflow:
1. eits tasks claim <task_id>
2. Implement using TDD (write test, verify fail, implement, verify pass)
3. Run: mix compile --warnings-as-errors
4. Commit your work
5. eits tasks complete <task_id> --message "<summary>"
6. DM orchestrator: eits dm --to <ORC_SESSION_UUID> --message "Task #<task_id> complete. <summary>"
```

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
eits teams list [--project <id>] [--status <active|inactive|all>] [--limit <n>]
eits teams get <id|name>
eits teams create --name <name> [--description <desc>] [--project <id>]
eits teams delete <id>
eits teams members <id>
eits teams join <team_id> --name <alias> [--role lead|member] [--session <uuid>]
eits teams status <id> [--wait] [--watch [<n>]] [--json]
# --wait   blocks until all members have member_status=done/spawn_failed (polls every 5s)
#          exits 0 when all done, 1 if any spawn_failed
#          bare invocation (no flags) prints a hint reminding you about --wait
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

`--team-name` and `--team-id` are mutually exclusive. Use `--team-id` when you have the integer ID and don't know the name — it resolves automatically via the teams API.

**Spawn output: extract session_uuid from the final compact summary line:**
```bash
session_uuid=$(eits agents spawn ... | tail -1 | jq -r '.session_uuid')
```

**Before spawning with `--worktree`, prune stale entries** to avoid name conflicts from prior rounds:
```bash
git worktree prune
```
The spawn command warns you if registered worktrees exist, but won't auto-prune.

---

## Designing the Work (do this BEFORE spawning)

Most failures in multi-agent work are not merge conflicts — they are **interface mismatches**. File-ownership boundaries only protect against mechanical conflicts; they don't protect against two agents disagreeing on what an assign, function signature, or return shape looks like. Walk through this decision tree before you touch `eits agents spawn`.

### Is the work actually parallelizable?

- **Orthogonal** (e.g. two independent bug fixes in separate contexts): fan out, no shared contract needed.
- **Producer/consumer** (A defines data, B renders it): **sequence them**, or give both a written contract. Parallel with hidden coupling is where wire-up gaps hide.
- **Single refactor touching one subsystem**: do not fan out. One agent, no team.

### Write the contract first

If two agents share any interface — assigns, function signatures, struct fields, return shapes, URL params — write it down **before** spawning. Drop a `/tmp/contract-<team>.md` with:

```md
# Shared contract v1

## Assigns
- @scope :: :all | integer
- @projects :: list(Project.t())  (always assigned by State.init)

## Return shapes
- Loader returns a list of maps; each map has :project_name key when scope == :all

## Wire-up
- ProjectLive.Sessions.render/1 MUST pass scope={@scope} projects={@projects} to <.page>
```

Every agent's instructions link to this file. Every reviewer checks against it. Every gap in the contract is a gap you will pay for in a follow-up commit.

### Carve file ownership + note interface coupling

Worker instructions must say two things:

1. **Files you own** (edit these).
2. **Files you MUST NOT touch** (merge-conflict guard).

File boundaries protect against the mechanical conflict. The contract doc protects against the logical conflict. You need both.

### Integration branch pattern for coupled work

When workers consume each other's interfaces, don't have them each branch from `main`:

```
main → integration-branch → worker-A, worker-B (both branch from integration)
worker-A merges back to integration
worker-B merges back to integration  (or pre-merges A to validate combined compile)
orchestrator does final glue commits on integration
PR integration → main
```

The orchestrator-only steps (router flips, file deletion, cross-cutting renames) live on integration, never in worker branches. This makes worker PRs reviewable in isolation while the integration PR shows the whole picture.

### Cross-peer review before the orchestrator reviews

After both workers DM done, have each peer-review the other's branch against the shared contract. Two independent reads of the same contract catch more gaps than one reviewer — when both reviewers independently flag the same gap, that convergence is the signal you got the contract tight.

Reviewers must cite `file:line` hunks in every finding. Ungrounded reviews produce hallucinated findings and waste an integration cycle.

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

`$EITS_SESSION_ID` (integer) is set reliably by the startup hook — use it directly. `--parent-session-id` accepts both integer and UUID. `ORC_AGENT_ID` still requires a psql lookup (no env var):

```bash
ORC_AGENT_ID=$(psql -d eits_dev -t -c "SELECT a.id FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$EITS_SESSION_UUID'" | tr -d ' ')
```

### 5. Spawn agents

Always include `parent_session_id` and `parent_agent_id` for proper session hierarchy. Prefer `$EITS_SESSION_ID` (integer) for `--parent-session-id` — both int and UUID work, but integer is canonical:

```bash
eits agents spawn \
  --instructions "Your task. team_id: <team_id>. When done, DM back: eits dm --to $EITS_SESSION_ID --message 'done'" \
  --model sonnet \
  --team-name my-team \
  --member-name researcher \
  --parent-session-id $EITS_SESSION_ID \
  --parent-agent-id $ORC_AGENT_ID
```

**Embed the orchestrator's integer session ID in DM-back instructions** — `$EITS_SESSION_ID` is shorter and unambiguous. UUID also works if you prefer.

Spawn all agents in parallel. Each gets a unique `--member-name`.

### 6. Monitor

**Preferred: block until all done** — eliminates shell gymnastics and stale-DM noise:

```bash
eits teams status <team_id> --wait
# Polls every 5s; prints [HH:MM:SS] waiting: N/M done, K pending
# Exits 0 when all done, 1 if any spawn_failed
# member_status is the authoritative signal — not session_status
```

For spot checks or ad-hoc DMs:
```bash
eits teams status <team_id>   # snapshot (also hints you about --wait)
eits dm --to $UUID_1 --message "Status update?"   # sequential only
eits dm --to $UUID_2 --message "Status update?"
```

### 7. Review and close out

After `--wait` exits, collect results. If agents DM-back with structured payloads, read them:

```bash
eits dm inbox --since-session   # only DMs since this session started; suppresses stale resume noise
```

If a specific agent's DM is needed before the team is fully done:
```bash
eits dm --to <agent_uuid_or_session_id> --message "Work complete. Run the task completion sequence and DM back."
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
eits tasks begin --title "<task name>"   # or: eits tasks begin --id <id> if orchestrator pre-assigned a task ID
# ... do work ...
eits tasks complete <task_id> --message "Summary of what was done"
# complete: annotates, marks done, sets team member status → done, DMs lead
```

If `complete` fails, fall back:

```bash
eits tasks annotate <task_id> --body "Summary"
eits tasks update <task_id> --state done
```

**Stop hook enforces completion** — `.claude/hooks/eits-task-gate.sh` blocks exit if any task is in state 2 linked to the session.

---

## Rules

- **Never manually insert DB records and spawn `claude` directly** — breaks `git_worktree_path`, session hierarchy, and "Load messages".
- **`--to` in `eits dm` accepts UUID or integer session ID** — both work.
- **DM sequentially** — parallel Bash DM calls cancel siblings on error.
- **Don't pass `--project-id` when `--parent-session-id` is set** — it's inherited.
- `--worktree` requires a clean working tree — commit or stash first.
- **Poll inbound DMs without the browser**: `eits dm list` shows the orchestrator's inbox; use `--session <uuid>` to check any member's inbox.

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

# 4. Get IDs — $EITS_SESSION_ID is integer, set by startup hook
ORC_AGENT_ID=$(psql -d eits_dev -t -c "SELECT a.id FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$EITS_SESSION_UUID'" | tr -d ' ')

# 5. Spawn agents — prefer $EITS_SESSION_ID (int) for --parent-session-id
eits agents spawn \
  --instructions "Investigate all claude --help flags. Write findings to /tmp/research.md. team_id: <team_id>. DM back to $EITS_SESSION_ID when done." \
  --model sonnet --team-name docs-team --member-name researcher \
  --parent-session-id $EITS_SESSION_ID --parent-agent-id $ORC_AGENT_ID

eits agents spawn \
  --instructions "Wait for /tmp/research.md, then write docs/README.md. team_id: <team_id>. DM back to $EITS_SESSION_ID when done." \
  --model sonnet --team-name docs-team --member-name writer \
  --parent-session-id $EITS_SESSION_ID --parent-agent-id $ORC_AGENT_ID

# 6. Monitor — block until all done
eits teams status <team_id> --wait

# Collect results (suppress stale DMs from prior sessions)
eits dm inbox --since-session
```

---

## Tips

- **Pass `team_id` in agent instructions** so they don't have to look it up.
- **Use descriptive `--member-name` values** — DMs identify agents by this alias.
- **Teams LiveView at `/teams`** — real-time member status and per-member task lists.
- **One team per logical unit of work** — don't reuse teams across unrelated tasks.
- **Task must be linked to session** for Stop hook to gate. `eits tasks claim` handles this. Verify: `psql -d eits_dev -c "SELECT task_id FROM task_sessions WHERE session_id = (SELECT id FROM sessions WHERE uuid = '$EITS_SESSION_UUID')"`

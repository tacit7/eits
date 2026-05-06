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

**Never redirect stderr on spawn:**
```bash
# WRONG — swallows errors silently; orchestrator thinks agent started, it never did
eits agents spawn ... 2>/dev/null

# RIGHT
eits agents spawn ...
```

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
merge integration → main
```

The orchestrator-only steps (router flips, file deletion, cross-cutting renames) live on integration, never in worker branches. This makes worker branches reviewable in isolation while the integration branch shows the whole picture.

### Cross-peer review before the orchestrator reviews

After both workers DM done, have each peer-review the other's branch against the shared contract. Two independent reads of the same contract catch more gaps than one reviewer — when both reviewers independently flag the same gap, that convergence is the signal you got the contract tight.

Reviewers must cite `file:line` hunks in every finding. Ungrounded reviews produce hallucinated findings and waste an integration cycle.

---

## Workflow

### 1. Create team

```bash
eits teams create --name "my-team" --description "What this team is doing" --project $EITS_PROJECT_ID
# Returns team_id
# ALWAYS pass --project — teams without it have project_id=null and won't appear
# in the /projects/:id/teams UI page.
# NOTE: the flag is --project, NOT --project-id (--project-id is an unknown flag here)
```

### 2. Join as orchestrator

Always pass `--session` explicitly — auto-resolve can silently produce NULL and break the DM link in the Teams UI:

```bash
eits teams join <team_id> --name "orchestrator" --role lead --session $EITS_SESSION_UUID
```

### 3. Create shared tasks

```bash
eits tasks create --title "Research X" --description "Details" --team <team_id>
# Use 'create' (not 'begin') here — creates the task in Todo state for workers to claim.
# 'begin' would mark it In Progress immediately, which is wrong for pre-assigned tasks.
# Workers claim with: eits tasks begin --id <task_id>
```

### 4. Get orchestrator IDs

`$EITS_SESSION_ID` (integer) is set reliably by the startup hook — use it directly. `--parent-session-id` accepts both integer and UUID. `ORC_AGENT_ID` still requires a psql lookup (no env var):

```bash
ORC_AGENT_ID=$(psql -d eits_dev -t -c "SELECT a.id FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$EITS_SESSION_UUID'" | tr -d ' ')
```

### 5. Spawn agents

Always include `parent_session_id` and `parent_agent_id` for proper session hierarchy. Use `--interpolate-env` whenever instructions reference `$EITS_SESSION_ID` or other env vars — without it the agent receives the literal string `"$EITS_SESSION_ID"`, not the integer:

```bash
eits agents spawn \
  --interpolate-env \
  --instructions "Your task. team_id: <team_id>. Run mix compile before finishing. DM back: eits dm --to $EITS_SESSION_ID --message 'done'" \
  --model sonnet \
  --team-name my-team \
  --member-name researcher \
  --parent-session-id $EITS_SESSION_ID \
  --parent-agent-id $ORC_AGENT_ID
```

**Each agent must have a unique `--worktree` name.** Duplicate names cause the second spawn to fail at the git layer with a confusing error.

**`EITS_PROJECT_ID` is NOT in spawned agent environments.** If agents need it, hardcode the value in instructions or use `--interpolate-env` so it expands from the orchestrator's env:

```bash
--interpolate-env \
--instructions "... EITS_PROJECT_ID=$EITS_PROJECT_ID ..."
```

Spawn all agents sequentially. Each gets a unique `--member-name`.

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
eits dm --to $UUID_1 --message "Status update?"   # sequential only — never parallel
eits dm --to $UUID_2 --message "Status update?"
# Parallel DM Bash calls share the same connection pool; the CLI cancels siblings on
# error, so one of the DMs silently never arrives.
```

### 7. Verify merges after --wait

`--wait` exits when all `member_status` fields settle — that is a task/status signal, not a git signal. Workers have DM'd done with unmerged branches. After `--wait`, verify each worker's branch was actually merged:

```bash
# Should show nothing if the branch was merged into main
git log --oneline main..<worktree-branch>

# Or just check the merge commit exists
git log --oneline --merges | head -5
```

### 8. Review and close out

After merges are confirmed, collect results:

```bash
eits dm inbox --since-session   # only DMs since this session started; suppresses stale resume noise
```

If a specific agent's DM is needed before the team is fully done:
```bash
eits dm --to <agent_uuid_or_session_id> --message "Work complete. Run the task completion sequence and DM back."
```

### 9. Shutdown

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
mix compile                              # MUST pass before DM-back — never DM done with a broken branch
eits tasks complete <task_id> --message "Summary of what was done"
# complete: annotates + marks task Done (one round-trip)
# team member_status → done fires automatically when the agent session ends (Stop hook)
# DM-back to orchestrator must be explicit — it is NOT sent by tasks complete
eits dm --to <ORC_SESSION_ID> --message "done:<branch-name>"
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
- **Never redirect stderr on `eits agents spawn`** — `2>/dev/null` swallows errors silently; the orchestrator thinks the agent started when it never did.
- **`--to` in `eits dm` accepts UUID or integer session ID** — both work.
- **DM sequentially** — parallel Bash DM calls cancel siblings on error, silently dropping messages.
- **Don't pass `--project-id` when `--parent-session-id` is set** — it's inherited.
- **`--worktree` names must be unique per spawn** — duplicates fail at the git layer with a confusing error.
- **`EITS_PROJECT_ID` is not in spawned agent environments** — pass it explicitly in instructions or via `--interpolate-env`.
- `--worktree` requires a clean working tree — commit or stash first.
- **Poll inbound DMs without the browser**: `eits dm list` shows the orchestrator's inbox; use `--session <uuid>` to check any member's inbox.

---

## Example: 2-Agent Research + Write

This example shows a **producer/consumer** pattern. Per the guidance above, sequence the writer after the researcher confirms done — do not spawn both in parallel.

```bash
# 1. Create team
eits teams create --name "docs-team" --description "Research flags and write README" --project $EITS_PROJECT_ID

# 2. Join as orchestrator
eits teams join <team_id> --name "orchestrator" --role lead --session $EITS_SESSION_UUID

# 3. Create tasks
eits tasks create --title "Research Claude CLI flags" --team <team_id>
eits tasks create --title "Write README from research" --team <team_id>

# 4. Get IDs — $EITS_SESSION_ID is integer, set by startup hook
ORC_AGENT_ID=$(psql -d eits_dev -t -c "SELECT a.id FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$EITS_SESSION_UUID'" | tr -d ' ')

# 5a. Spawn researcher first
eits agents spawn \
  --interpolate-env \
  --instructions "Investigate all claude --help flags. Write findings to /tmp/research.md. team_id: <team_id>. Run mix compile. DM back to $EITS_SESSION_ID when done." \
  --model sonnet --team-name docs-team --member-name researcher \
  --parent-session-id $EITS_SESSION_ID --parent-agent-id $ORC_AGENT_ID

# 6a. Wait for researcher
eits teams status <team_id> --wait

# 5b. Only then spawn writer (producer/consumer — must be sequenced)
eits agents spawn \
  --interpolate-env \
  --instructions "Read /tmp/research.md and write docs/README.md. team_id: <team_id>. Run mix compile. DM back to $EITS_SESSION_ID when done." \
  --model sonnet --team-name docs-team --member-name writer \
  --parent-session-id $EITS_SESSION_ID --parent-agent-id $ORC_AGENT_ID

# 6b. Wait for writer
eits teams status <team_id> --wait

# 7. Verify merges, then collect results
eits dm inbox --since-session
```

---

## Tips

- **Pass `team_id` in agent instructions** so they don't have to look it up.
- **Use descriptive `--member-name` values** — DMs identify agents by this alias.
- **Teams LiveView at `/teams`** — real-time member status and per-member task lists.
- **One team per logical unit of work** — don't reuse teams across unrelated tasks.
- **Task must be linked to session** for Stop hook to gate. `eits tasks claim` handles this. Verify: `psql -d eits_dev -c "SELECT task_id FROM task_sessions WHERE session_id = (SELECT id FROM sessions WHERE uuid = '$EITS_SESSION_UUID')"`

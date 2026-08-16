---
name: eits-team-worker
description: >
  Use when you are a spawned EITS team member executing an assigned task — claiming
  the task, working inside an isolated worktree, respecting file-ownership and contract
  boundaries, compiling, completing the task, and DMing the orchestrator back. Triggers
  when spawned with team_id/--member-name in your instructions, or on "I'm an EITS team worker",
  "I was spawned to", "claim my task", "DM back when done".
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# EITS Team Worker

You were spawned as a member of an EITS team to execute **one scoped task**. This skill
is the worker counterpart to `eits-teams` (the orchestrator side). Your job: claim the
task, do exactly the assigned work in your worktree, compile, complete, and DM back.

**Two failures dominate team work, and both are silent:**

1. **Forgetting to claim the task before working.** If you call `eits tasks complete`
   without first calling `eits tasks begin --id <id>`, the task is never linked to your
   session. The team detail page groups tasks by the session link in `task_sessions`, so
   your finished work shows up under **"Unassigned"** forever — and once the task is Done
   it can no longer be claimed/reassigned. Claim first, always.
2. **Forgetting the explicit DM-back.** `eits tasks complete` and the Stop hook settle
   your `member_status`, but they do NOT message the orchestrator. If you don't DM back,
   the orchestrator blocks waiting on you.

---

## Your Instructions Carry the Contract

Read your spawn instructions carefully before touching anything. They will name some or all of:

- **Your task** — a title, or a pre-assigned task ID to claim (`eits tasks begin --id <id>`).
- **`team_id`** — pass this through; don't look it up.
- **Files you own** — edit only these.
- **Files you MUST NOT touch** — the merge-conflict guard. Honor it strictly.
- **A contract doc** (often `/tmp/contract-<team>.md`) — assigns, function signatures,
  struct fields, return shapes, wire-up. **Read it first and build to it exactly.** An
  interface mismatch against the contract is a guaranteed follow-up integration cycle.
- **A DM-back target** — the orchestrator session ID (integer) or UUID.
- **`EITS_PROJECT_ID`** — it is NOT inherited in Claude agent environments. Use the value
  given in your instructions.

If the instructions are ambiguous about scope or interface, DM the orchestrator and ask
**before** writing code — a 1-sentence clarification is cheaper than a wrong implementation.

---

## Lifecycle

### 1. Claim your task (MUST be first — gates AND team assignment depend on it)

```bash
# Orchestrator pre-assigned a task ID (the common case):
eits tasks begin --id <task_id>          # claims + links to your session + sets In Progress

# No pre-assigned task:
eits tasks begin --title "<what you're doing>"
```

Poll the inbox before claiming and after the claim:

```bash
eits dm inbox --since-session --team-only --json
```

**Why this must come first, before any edit:**

- The Stop hook (`.claude/hooks/eits-task-gate.sh`) blocks exit while a state-2 task is
  open, and the edit gate blocks edits before one exists.
- **`begin --id` is what links the task to YOUR session.** It removes the orchestrator's
  session link (the task was created by them) and inserts yours. The team page reads that
  link to file the task under your column. Skip this step and your work lands in
  "Unassigned" — `complete` alone never touches `task_sessions`.

### 2. Read the contract, then do the work

- Read the contract doc and any files you'll touch before editing.
- Stay inside your file-ownership boundary. Do **not** "clean up" or refactor adjacent code.
- No scope creep — deliver the assigned task, nothing more.

### 3. Compile before you finish — non-negotiable

```bash
mix compile --warnings-as-errors
```

**Never DM done with a broken branch.** A worker that DMs `done` on code that doesn't
compile poisons the integration branch and burns an orchestrator cycle. Errors are not
acceptable; warnings are.

### 4. Log commits

```bash
git commit -m "..."                      # clean message; no Claude/Anthropic attribution
eits commits create --hash <hash>        # log every commit you make
```

### 5. Complete the task

```bash
eits tasks complete <task_id> --message "What was done — summary IS the handoff record"
```

Before completing, poll the inbox again so late orchestrator feedback is not missed:

```bash
eits dm inbox --since-session --team-only --json
```

Fallback if `complete` fails:

```bash
eits tasks annotate <task_id> --body "Summary"
eits tasks update <task_id> --state done
```

### 6. DM the orchestrator back — explicit, always

```bash
eits dm --to <ORC_SESSION_ID> --message "done:<branch-name>"
eits dm inbox --since-session --team-only --json   # catch any follow-up after the done DM
```

- `tasks complete` does NOT send this. The Stop hook flips your `member_status` to `done`
  automatically when your session ends, but the orchestrator still needs the DM to know
  your branch is ready and what it's called.
- Keep it short. Name the branch so the orchestrator can merge without asking.
- If your work is blocked or incomplete, DM that instead — say what's blocking and why.

---

## Rules

- **Claim a task before editing.** No exceptions — both gates enforce it, and it is the
  only thing that links the task to you for the team page.
- **DM back explicitly when done.** `complete` + Stop hook ≠ a message to the orchestrator.
- **Poll team DMs at checkpoints.** Run `eits dm inbox --since-session --team-only --json` before claiming, after major transitions, before completing, and after the done DM.
- **`mix compile` must pass** before completing/DMing. Never hand off a broken branch.
- **Respect file ownership.** Touch only the files you own; never the forbidden list.
- **Build to the contract.** Interface drift is the #1 cause of integration rework.
- **No scope creep.** One task, in scope, done well.
- **`EITS_PROJECT_ID` is not in your env** — use the value from your instructions.
- **Clean commit messages** — strip Claude/Anthropic attribution and co-author tags.
- **Codex LGTM before merge** is the orchestrator's job, not yours — just DM the branch.

---

## Quick Reference

| Step | Command |
|------|---------|
| Claim assigned task (FIRST) | `eits tasks begin --id <task_id>` |
| Claim new task | `eits tasks begin --title "..."` |
| Compile gate | `mix compile --warnings-as-errors` |
| Log commit | `eits commits create --hash <hash>` |
| Complete task | `eits tasks complete <id> --message "..."` |
| DM orchestrator | `eits dm --to <ORC_SESSION_ID> --message "done:<branch>"` |
| Poll team inbox | `eits dm inbox --since-session --team-only --json` |

See `eits-teams` for the orchestrator side, `eits-dm` for DM details, and `eits-workflow`
for the full task/commit/note CLI.

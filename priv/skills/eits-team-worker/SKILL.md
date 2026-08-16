---
name: eits-team-worker
description: >
  Use when you are a spawned EITS team member implementing or changing code in an
  assigned worktree — respecting file ownership, contract boundaries, validation,
  commits, and handoff quality. Pair with eits-team-member for the mandatory claim,
  inbox, completion, and DM-back protocol.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# EITS Team Worker

You were spawned as a member of an EITS team to execute **one scoped task**. This skill
is the implementation discipline layer for team work. Use `eits-team-member` for the
mandatory runtime protocol: inbox checkpoints, task claim, completion, and explicit
DM-back. Use `eits-teams` for the orchestrator side.

**Two failures dominate team work, and both are silent:**

1. **Forgetting to claim the task before working.** If you call `eits tasks complete`
   without first calling `eits tasks claim <id>`, the task is never linked to your
   session. The team detail page groups tasks by the session link in `task_sessions`, so
   your finished work shows up under **"Unassigned"** forever — and once the task is Done
   it can no longer be claimed/reassigned. Claim first, always.
2. **Forgetting the explicit DM-back.** `eits tasks complete` and the Stop hook settle
   your `member_status`, but they do NOT message the orchestrator. If you don't DM back,
   the orchestrator blocks waiting on you.

---

## Your Instructions Carry the Contract

Read your spawn instructions carefully before touching anything. They will name some or all of:

- **Your task** — a title, or a pre-assigned task ID to claim (`eits tasks claim <id>`).
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

### 1. Follow the member protocol first

Load and follow `eits-team-member` before editing. In short:

```bash
eits dm inbox --since-session --team-only --json
eits tasks claim <task_id>
eits dm inbox --since-session --team-only --json
```
**Why this must come first, before any edit:**

- The Stop hook (`.claude/hooks/eits-task-gate.sh`) blocks exit while a state-2 task is
  open, and the edit gate blocks edits before one exists.
- **`tasks claim` is what links the task to YOUR session.** It removes the orchestrator's
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

### 5. Complete and DM back

Follow `eits-team-member` for the exact completion and DM sequence. The required
DM shape is:

```text
done task=<task_id> result=<summary> branch=<branch-or-pr> commit=<sha-or-none>
```

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
| Claim assigned task (FIRST) | `eits tasks claim <task_id>` |
| Claim new task | `eits tasks begin --title "..."` |
| Compile gate | `mix compile --warnings-as-errors` |
| Log commit | `eits commits create --hash <hash>` |
| Complete task | `eits tasks complete <id> --message "..."` |
| DM orchestrator | `eits dm --to <ORC_SESSION_ID> --message "done task=<id> result=<summary> branch=<branch> commit=<sha-or-none>"` |
| Poll team inbox | `eits dm inbox --since-session --team-only --json` |

See `eits-team-member` for the required member protocol, `eits-teams` for the
orchestrator side, `eits-dm` for DM details, and `eits-workflow` for the full
task/commit/note CLI.

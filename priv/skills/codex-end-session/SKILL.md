---
name: codex-end-session
description: Clean session close for Codex agents. Completes in-progress tasks, logs commits, and marks the session done. Use when a Codex agent is finishing its work.
---

# Codex End Session

## Steps

1. **Check for in-progress tasks**:
   ```bash
   psql -d eits_dev -tAq -c "
     SELECT t.id, t.title FROM tasks t
     JOIN task_sessions ts ON ts.task_id = t.id
     JOIN sessions s ON s.id = ts.session_id
     WHERE s.uuid = '$EITS_SESSION_UUID'
       AND t.workflow_state_id = 2
   "
   ```
   For each: annotate then complete:
   ```bash
   eits tasks annotate <id> --body "Summary of work done"
   eits tasks complete <id> --message "Summary"
   ```
   Fallback:
   ```bash
   eits tasks annotate <id> --body "Summary"
   eits tasks update <id> --state 4
   ```

2. **Log any unlogged commits** (PostToolUse hook does this automatically; verify):
   ```bash
   git log --oneline -5
   eits commits create --hash <hash> --message "<msg>"
   ```

3. **Set session status**:
   - Spawned agent: `eits sessions update $EITS_SESSION_UUID --status waiting`
   - Interactive: `eits sessions update $EITS_SESSION_UUID --status completed`

   The Stop hook sets `stopped` automatically. This step sets the final terminal status.

4. **Output summary** — what was done, commits logged, follow-up items.

## Note on Stop Hook

The Stop hook (`codex-session-stop.sh`) will exit 2 and block if any task is in-progress without annotation. Step 1 above clears that gate. Always run it before declaring done.

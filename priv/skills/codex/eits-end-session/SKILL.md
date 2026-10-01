---
name: eits-end-session
description: Clean session close for Codex agents. Completes in-progress tasks, logs commits, and marks the session idle or completed. Use when a Codex agent is finishing its work.
---

# Codex End Session

## Codex Runtime Notes

- Codex agents use the `eits` CLI directly. Do not emit `EITS-CMD:` directives and do not gate CLI usage on `CLAUDE_CODE_ENTRYPOINT`.
- Codex startup hooks may persist non-secret identity vars to `~/.eits/codex/sessions/<session_id>.env`. Plain `eits` calls auto-load that file only when `EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set.
- For shell commands that expand `$EITS_SESSION_UUID`, `$EITS_SESSION_ID`, `$EITS_AGENT_UUID`, `$EITS_AGENT_ID`, or `$EITS_PROJECT_ID`, source the session env in the same command when needed:

```bash
. ~/.eits/codex/sessions/<session_id>.env 2>/dev/null || true
```

- Use `$EITS_SESSION_UUID` for UUID-only commands and `$EITS_SESSION_ID` for integer session contexts. If no Codex session id or EITS env is known, ask the user before running identity-scoped commands.

## Steps

1. Check for in-progress tasks:
   ```bash
   eits tasks active --json
   ```
   For each in-progress task, annotate and complete it:
   ```bash
   eits tasks annotate <id> --body "Summary of work done"
   eits tasks complete <id> --message "Summary"
   ```
   Fallback:
   ```bash
   eits tasks annotate <id> --body "Summary"
   eits tasks update <id> --state done
   ```

2. Log any unlogged commits. The `PostToolUse/Bash` hook normally logs commits automatically; verify when in doubt:
   ```bash
   git log --oneline -5
   eits commits create --hash <hash>
   ```

3. Set session status:
   ```bash
   eits sessions update "$EITS_SESSION_UUID" --status idle
   ```
   Use `completed` only when the user explicitly wants the session fully done rather than resumable.

4. Output a concise summary: work done, tasks completed, commits logged, and any follow-up.

## Stop Hook

The Codex Stop hook can block if any linked task is still in progress without an annotation. Always annotate and complete or intentionally hand off in-progress tasks before declaring done.

## Rules

- Only commit when there are actual changes to commit.
- Do not use Claude slash commands such as `/i-update-status` or `/commit-work`; Codex uses direct shell commands and the `eits` CLI.
- Do not use `i-speak`; report the summary in the final response.
- Keep the summary short and actionable.

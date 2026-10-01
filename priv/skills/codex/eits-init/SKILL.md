---
name: eits-init
description: Initialize EITS session tracking for a Codex agent or verify Codex EITS env vars. Use when starting a Codex session, when hooks may not have run, or when EITS identity needs verification.
---

# Codex EITS Init

## Codex Runtime Notes

- Codex agents use the `eits` CLI directly. Do not emit `EITS-CMD:` directives and do not gate CLI usage on `CLAUDE_CODE_ENTRYPOINT`.
- Codex startup hooks may persist non-secret identity vars to `~/.eits/codex/sessions/<session_id>.env`. Plain `eits` calls auto-load that file only when `EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set.
- For shell commands that expand `$EITS_SESSION_UUID`, `$EITS_SESSION_ID`, `$EITS_AGENT_UUID`, `$EITS_AGENT_ID`, or `$EITS_PROJECT_ID`, source the session env in the same command when needed:

```bash
. ~/.eits/codex/sessions/<session_id>.env 2>/dev/null || true
```

- Use `$EITS_SESSION_UUID` for UUID-only commands and `$EITS_SESSION_ID` for integer session contexts. If no Codex session id or EITS env is known, ask the user before running identity-scoped commands.

EITS env vars are normally pre-injected by AgentWorker before the session starts. For Codex hook sessions, startup also writes non-secret identity vars to `~/.eits/codex/sessions/<session_id>.env`.

| Variable | Description |
|----------|-------------|
| `EITS_SESSION_UUID` | Session UUID |
| `EITS_SESSION_ID` | Integer session ID |
| `EITS_AGENT_UUID` | Agent UUID |
| `EITS_AGENT_ID` | Integer agent ID |
| `EITS_PROJECT_ID` | Project integer ID |
| `EITS_URL` | `http://localhost:5001/api/v1` |

## Steps

1. Check if already initialized:
   ```bash
   echo "$EITS_AGENT_UUID"
   ```
   Non-empty -> already initialized, exit.

2. Verify env vars:
   ```bash
   echo "Session: $EITS_SESSION_UUID ($EITS_SESSION_ID) | Agent: $EITS_AGENT_UUID ($EITS_AGENT_ID) | Project: $EITS_PROJECT_ID | URL: ${EITS_URL:-http://localhost:5001/api/v1}"
   ```

3. Check if the session exists:
   ```bash
   eits sessions get "$EITS_SESSION_UUID"
   ```
   HTTP 200 -> skip to status update. Otherwise create:
   ```bash
   eits sessions create \
     --session-id "$EITS_SESSION_UUID" \
     --name "<name>" \
     --description "<description>" \
     --project "<project_name>" \
     --model "codex"
   ```

4. Set status to working if hooks are not active:
   ```bash
   eits sessions update "$EITS_SESSION_UUID" --status working
   ```

5. Report: `EITS active. Agent: $EITS_AGENT_UUID Project: $EITS_PROJECT_ID`.

## Hooks

Codex lifecycle hooks require both `.codex/hooks.json` at repo root and this feature flag in `~/.codex/config.toml`:

```toml
[features]
hooks = true
```

When enabled, these run automatically:

- `SessionStart` -> `codex-session-startup.sh` registers/resolves the session without marking busy
- `UserPromptSubmit` -> `eits-codex-notify.sh` sets status=working
- `PostToolUse/Bash` -> `eits-codex-notify.sh` records tool activity and logs git commits
- `PreCompact` -> `eits-codex-notify.sh` sets status=compacting
- `Stop` -> `eits-codex-notify.sh` sets status=idle and enforces task annotation

Scripts live in `priv/scripts/`.

## CLI Reference

| Operation | Command |
|-----------|---------|
| Get session | `eits sessions get $EITS_SESSION_UUID` |
| Update session | `eits sessions update $EITS_SESSION_UUID [--status <s>] [--intent <text>] [--entrypoint <e>]` |
| End session | `eits sessions end $EITS_SESSION_UUID` |
| Get session context | `eits sessions context $EITS_SESSION_UUID` |
| Create + start task | `eits tasks begin --title <t>` |
| Claim assigned task | `eits tasks claim <id>` |
| Complete task | `eits tasks complete <id> --message <text>` |
| Update state by alias | `eits tasks update <id> --state done` |
| Annotate task | `eits tasks annotate <id> --body <text>` |
| Add note | `eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --body <text>` |
| Log commits | `eits commits create --hash <h1> [--hash <h2>]` |

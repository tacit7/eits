---
name: codex-init
description: Initialize EITS session tracking for a Codex agent at session start. Use when starting a new Codex session or when EITS env vars need verification.
---

# Codex EITS Init

EITS env vars are pre-injected by AgentWorker before the session starts.

| Variable | Description |
|----------|-------------|
| `EITS_SESSION_UUID` | Session UUID |
| `EITS_SESSION_ID` | Integer session ID |
| `EITS_AGENT_UUID` | Agent UUID |
| `EITS_PROJECT_ID` | Project integer ID |
| `EITS_URL` | `http://localhost:5001/api/v1` |

## Steps

1. **Check if already initialized**:
   ```bash
   echo "$EITS_AGENT_UUID"
   ```
   Non-empty → already initialized, exit.

2. **Verify env vars**:
   ```bash
   echo "Session: $EITS_SESSION_UUID | Project: $EITS_PROJECT_ID | URL: $EITS_URL"
   ```

3. **Check if session exists**:
   ```bash
   eits sessions get $EITS_SESSION_UUID
   ```
   HTTP 200 → skip to step 4. Otherwise create:
   ```bash
   eits sessions create \
     --session-id $EITS_SESSION_UUID \
     --name "<name>" \
     --description "<description>" \
     --project "<project_name>" \
     --model "codex"
   ```

4. **Set status to working** (UserPromptSubmit hook handles this automatically; do it manually if hooks are not active):
   ```bash
   eits sessions update $EITS_SESSION_UUID --status working
   ```

5. **Report**: `"EITS active. Agent: $EITS_AGENT_UUID  Project: $EITS_PROJECT_ID"`

## Hooks

If `.codex/hooks.json` is present at repo root, these run automatically:
- `SessionStart` → `eits-codex-notify.sh` routes startup/resume bookkeeping without marking busy
- `UserPromptSubmit` → `eits-codex-notify.sh` sets status=working
- `PostToolUse/Bash` → `eits-codex-notify.sh` records tool activity and logs git commits
- `PreCompact` → `eits-codex-notify.sh` sets status=compacting
- `Stop` → `eits-codex-notify.sh` sets status=idle + enforces annotation

Scripts live in `priv/scripts/`.

#!/bin/bash
# EITS Session Compaction Hook (Go MCP Server)
# Fires on SessionStart(compact) — compaction is complete at this point.
# Sets status back to working; PreCompact hook set it to compacting.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAPPING_FILE="$HOME/.claude/hooks/session_agent_map.json"
LOG_FILE="$HOME/.config/eye-in-the-sky/compact-hook.log"

# Parse input from Claude Code
INPUT=$(cat)

# Log raw input for debugging
echo "$(date -Iseconds) COMPACT INPUT: $INPUT" >> "$LOG_FILE"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
  echo "[EITS] Compact: no session_id, skipping" >&2
  exit 0
fi

# Log what we found
echo "$(date -Iseconds) COMPACT: session=$SESSION_ID" >> "$LOG_FILE"

BASE=${EITS_API_URL:-http://localhost:5001/api/v1}

# Compaction done — set status back to working via REST
curl -sk -X PATCH "$BASE/sessions/$SESSION_ID" \
  -H 'Content-Type: application/json' \
  -d '{"status":"working"}' >/dev/null 2>&1

echo "[EITS] Compact: done, session $SESSION_ID back to working" >&2

# Publish to NATS
"$HOOK_DIR/nats/publish-session-compact.sh" "$SESSION_ID" "working"

# Remove old mapping so init hook can register fresh session
if [ -f "$MAPPING_FILE" ]; then
  UPDATED=$(jq "del(.\"$SESSION_ID\")" "$MAPPING_FILE" 2>/dev/null) || true
  [ -n "$UPDATED" ] && echo "$UPDATED" > "$MAPPING_FILE"
fi

exit 0

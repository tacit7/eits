#!/bin/bash
# EITS Session Compaction Hook (Go MCP Server)
# Fires on SessionStart(compact) — compaction is complete at this point.
# Sets status back to working; PreCompact hook set it to compacting.

set -uo pipefail

# --- EITS Workflow Guard ---
EITS_WORKFLOW="${EITS_WORKFLOW:-}"
if [ -z "$EITS_WORKFLOW" ]; then
  EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}"
  ENABLED=$(curl -sf "${EITS_URL}/settings/eits_workflow_enabled" 2>/dev/null | jq -r '.enabled' 2>/dev/null || echo "true")
  [ "$ENABLED" = "false" ] && exit 0
elif [ "$EITS_WORKFLOW" = "0" ]; then
  exit 0
fi
# --- End Workflow Guard ---

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

# Compaction done — set status back to working via eits CLI
EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}" eits sessions update "$SESSION_ID" --status working >/dev/null 2>&1 || true

echo "[EITS] Compact: done, session $SESSION_ID back to working" >&2

# Publish to NATS
"$HOOK_DIR/nats/publish-session-compact.sh" "$SESSION_ID" "working"

# Remove old mapping so init hook can register fresh session
if [ -f "$MAPPING_FILE" ]; then
  UPDATED=$(jq "del(.\"$SESSION_ID\")" "$MAPPING_FILE" 2>/dev/null) || true
  [ -n "$UPDATED" ] && echo "$UPDATED" > "$MAPPING_FILE"
fi

exit 0

#!/bin/bash
# EITS Session Compaction Hook (Go MCP Server)
# Fires on SessionStart(compact)
# Marks old session as compacted, removes from mapping

set -e

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

# Mark old session as compacted (SQL)
"$HOOK_DIR/sql/update-session-status.sh" "$SESSION_ID" "compacted"

echo "[EITS] Compact: marked session $SESSION_ID as compacted" >&2

# Publish to NATS
"$HOOK_DIR/nats/publish-session-compact.sh" "$SESSION_ID" "compacted"

# Remove old mapping so init hook can register fresh session
if [ -f "$MAPPING_FILE" ]; then
  UPDATED=$(jq "del(.\"$SESSION_ID\")" "$MAPPING_FILE" 2>/dev/null) || true
  [ -n "$UPDATED" ] && echo "$UPDATED" > "$MAPPING_FILE"
fi

exit 0

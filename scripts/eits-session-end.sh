#!/usr/bin/env bash
# Hook: Mark session as completed on SessionEnd and sync messages
# Uses SQLite directly (Go MCP server version)
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EITS_DB="$HOME/.config/eye-in-the-sky/eits.db"
MCP_BIN="$HOME/projects/eits/core/bin/eits-mcp-server"

# Parse stdin JSON for session info
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Update session status to completed (SQL)
"$HOOK_DIR/sql/update-session-status.sh" "$session_id" "completed"

# Publish to NATS
"$HOOK_DIR/nats/publish-session-end.sh" "$session_id" "completed"

# Sync messages from .jsonl to database (if MCP server binary exists)
if [ -x "$MCP_BIN" ]; then
    echo "[EITS] Syncing messages to database..." >&2
    timeout 30 "$MCP_BIN" --db "$EITS_DB" i-sync-messages --session-id "$session_id" 2>/dev/null || true
fi

exit 0

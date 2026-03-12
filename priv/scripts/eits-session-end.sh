#!/usr/bin/env bash
# Hook: Mark session as completed on SessionEnd
# Also moves any in-progress tasks linked to this session to In Review (state_id=4)
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=${EITS_API_URL:-http://localhost:5001/api/v1}

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"
_pgq() { psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A -c "$1" 2>/dev/null; }

# Parse stdin JSON for session info
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Move any in-progress tasks linked to this session to In Review (state_id=4)
# This is a safety net in case the agent didn't do it manually
_pgq "
  UPDATE tasks t
  SET state_id = 4, updated_at = NOW()
  FROM task_sessions ts
  JOIN sessions s ON s.id = ts.session_id
  WHERE t.id = ts.task_id
    AND s.uuid = '$session_id'
    AND t.state_id = 2
    AND t.archived = false
" || true

# Update session status to completed via REST
curl -sk -X PATCH "$BASE/sessions/$session_id" \
  -H 'Content-Type: application/json' \
  -d '{"status":"completed"}' >/dev/null 2>&1

# Publish to NATS
"$HOOK_DIR/nats/publish-session-end.sh" "$session_id" "completed"

exit 0

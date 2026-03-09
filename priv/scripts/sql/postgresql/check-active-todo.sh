#!/usr/bin/env bash
# Check if session has an active todo (state_id = 2)
# Args: $1 = session_id (UUID)
# Returns: 0 if active todo exists, 1 if not
set -euo pipefail

session_id="${1:-}"
[ -z "$session_id" ] && exit 1

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"

active_todo_count=$(psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A -c "
  SELECT COUNT(*)
  FROM tasks t
  JOIN task_sessions ts ON t.id = ts.task_id
  JOIN sessions s ON s.id = ts.session_id
  WHERE s.uuid = '$session_id'
  AND t.state_id = 2
  AND t.archived = false
" 2>/dev/null) || active_todo_count=0

[ "$active_todo_count" -gt 0 ]

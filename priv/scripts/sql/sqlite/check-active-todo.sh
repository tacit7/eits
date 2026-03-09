#!/usr/bin/env bash
# Check if session has an active todo (state_id = 2)
# Args: $1 = session_id (UUID)
# Returns: 0 if active todo exists, 1 if not
set -euo pipefail

session_id="${1:-}"
[ -z "$session_id" ] && exit 1

db_path="${EITS_DB_PATH:-$HOME/.config/eye-in-the-sky/eits.db}"

active_todo_count=$(sqlite3 "$db_path" "
  SELECT COUNT(*)
  FROM tasks t
  JOIN task_sessions ts ON t.id = ts.task_id
  JOIN sessions s ON s.id = ts.session_id
  WHERE s.uuid = '$session_id'
  AND t.state_id = 2
  AND t.archived = 0
" 2>/dev/null) || active_todo_count=0

[ "$active_todo_count" -gt 0 ]

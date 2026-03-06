#!/usr/bin/env bash
# Update session status
# Args: $1 = session_id (UUID), $2 = status
set -euo pipefail

session_id="${1:-}"
status="${2:-}"
[ -z "$session_id" ] || [ -z "$status" ] && exit 1

db_path="${EITS_DB_PATH:-$HOME/.config/eye-in-the-sky/eits.db}"

sqlite3 "$db_path" "
  UPDATE sessions
  SET status = '$status',
      last_activity_at = CURRENT_TIMESTAMP
  WHERE uuid = '$session_id'
" 2>/dev/null || exit 0

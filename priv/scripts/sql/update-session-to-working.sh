#!/usr/bin/env bash
# Update session to working status (only if not already working)
# Args: $1 = session_id (UUID)
set -euo pipefail

session_id="${1:-}"
[ -z "$session_id" ] && exit 1

db_path="${EITS_DB_PATH:-$HOME/.config/eye-in-the-sky/eits.db}"

# Check current status
current_status=$(sqlite3 "$db_path" "
  SELECT status FROM sessions WHERE uuid = '$session_id'
" 2>/dev/null) || exit 0

# Skip if already working
[ "$current_status" = "working" ] && exit 0

# Update to working
sqlite3 "$db_path" "
  UPDATE sessions
  SET status = 'working',
      last_activity_at = CURRENT_TIMESTAMP
  WHERE uuid = '$session_id'
" 2>/dev/null || exit 0

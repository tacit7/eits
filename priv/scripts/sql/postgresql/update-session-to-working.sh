#!/usr/bin/env bash
# Update session to working status (only if not already working)
# Args: $1 = session_id (UUID)
set -euo pipefail

session_id="${1:-}"
[ -z "$session_id" ] && exit 1

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"

current_status=$(psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A -c "
  SELECT status FROM sessions WHERE uuid = '$session_id'
" 2>/dev/null) || exit 0

# Skip if already working
[ "$current_status" = "working" ] && exit 0

psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -c "
  UPDATE sessions
  SET status = 'working',
      last_activity_at = NOW()
  WHERE uuid = '$session_id'
" 2>/dev/null || exit 0

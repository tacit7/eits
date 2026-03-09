#!/usr/bin/env bash
# Update session intent field
# Args: $1 = session_uuid, $2 = intent text
set -euo pipefail

session_uuid="${1:-}"
intent="${2:-}"

[ -z "$session_uuid" ] && exit 1

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"

# Escape single quotes for PostgreSQL
intent_escaped="${intent//\'/\'\'}"

psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -c "
  UPDATE sessions
  SET intent = '$intent_escaped',
      last_activity_at = NOW()
  WHERE uuid = '$session_uuid'
" 2>/dev/null || true

#!/usr/bin/env bash
# Update agent status
# Args: $1 = agent_id (UUID), $2 = status
set -euo pipefail

agent_id="${1:-}"
status="${2:-}"
[ -z "$agent_id" ] || [ -z "$status" ] && exit 1

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"

psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -c "
  UPDATE agents
  SET status = '$status',
      last_activity_at = to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  WHERE uuid = '$agent_id'
" 2>/dev/null || exit 0

#!/usr/bin/env bash
# Update agent status
# Args: $1 = agent_id (UUID), $2 = status
set -euo pipefail

agent_id="${1:-}"
status="${2:-}"
[ -z "$agent_id" ] || [ -z "$status" ] && exit 1

db_path="${EITS_DB_PATH:-$HOME/.config/eye-in-the-sky/eits.db}"

sqlite3 "$db_path" "
  UPDATE agents
  SET status = '$status',
      last_activity_at = CURRENT_TIMESTAMP
  WHERE uuid = '$agent_id'
" 2>/dev/null || exit 0

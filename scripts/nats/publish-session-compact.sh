#!/usr/bin/env bash
# Publish session compact event to NATS
# Args: $1 = session_id, $2 = status (default: compacted)
set -euo pipefail

session_id="${1:-}"
status="${2:-compacted}"

[ -z "$session_id" ] && exit 0

nats pub "events.session.compact" "$(jq -nc \
  --arg session_id "$session_id" \
  --arg status "$status" \
  '{session_id: $session_id, data: {status: $status}}')" 2>/dev/null &

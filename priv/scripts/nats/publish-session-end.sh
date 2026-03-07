#!/usr/bin/env bash
# Publish session end event to NATS
# Args: $1 = session_id, $2 = status (default: completed)
set -euo pipefail

session_id="${1:-}"
status="${2:-completed}"

[ -z "$session_id" ] && exit 0

nats pub "events.session.end" "$(jq -nc \
  --arg session_id "$session_id" \
  --arg status "$status" \
  '{session_id: $session_id, data: {status: $status}}')" 2>/dev/null &

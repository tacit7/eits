#!/usr/bin/env bash
# Check if session has an active todo (state_id = 2) via eits CLI
# Args: $1 = session_id (UUID)
# Returns: 0 if active todo exists, 1 if not
set -euo pipefail

session_id="${1:-}"
[ -z "$session_id" ] && exit 1

count=$(eits tasks list --session "$session_id" --state 2 2>/dev/null \
  | jq -r '.tasks | length' 2>/dev/null) || count=0

[ "${count:-0}" -gt 0 ]

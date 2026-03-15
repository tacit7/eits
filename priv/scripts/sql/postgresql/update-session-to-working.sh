#!/usr/bin/env bash
# Update session to working status via eits CLI
# Args: $1 = session_id (UUID)
set -euo pipefail

session_id="${1:-}"
[ -z "$session_id" ] && exit 1

eits sessions update "$session_id" --status working > /dev/null 2>&1 || true

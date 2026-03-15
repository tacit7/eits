#!/usr/bin/env bash
# Update session status via eits CLI
# Args: $1 = session_id (UUID), $2 = status
set -euo pipefail

session_id="${1:-}"
status="${2:-}"
[ -z "$session_id" ] || [ -z "$status" ] && exit 1

eits sessions update "$session_id" --status "$status" > /dev/null 2>&1 || true

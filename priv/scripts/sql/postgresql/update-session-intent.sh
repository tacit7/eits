#!/usr/bin/env bash
# Update session intent field via eits CLI
# Args: $1 = session_uuid, $2 = intent text
set -euo pipefail

session_uuid="${1:-}"
intent="${2:-}"
[ -z "$session_uuid" ] && exit 1

eits sessions update "$session_uuid" --intent "$intent" > /dev/null 2>&1 || true

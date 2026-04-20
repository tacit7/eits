#!/bin/bash
# EITS Session Compaction Hook
# Fires on SessionStart(compact) — compaction is complete at this point.
# Sets status back to working; PreCompact hook set it to compacting.
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"


INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")

[ -z "$SESSION_ID" ] && exit 0

eits sessions update "$SESSION_ID" --status working >/dev/null 2>&1 || true

exit 0

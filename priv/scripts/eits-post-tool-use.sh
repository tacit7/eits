#!/usr/bin/env bash
# Hook: PostToolUse — currently a no-op, reserved for future tool result tracking
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

exit 0

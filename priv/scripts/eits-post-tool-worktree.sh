#!/usr/bin/env bash
# PostToolUse hook: detect `git worktree add` and attach the worktree path
# to the current session via PATCH /api/v1/sessions/:uuid.
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ "$tool_name" != "Bash" ] && exit 0

command=$(echo "$input_json" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ "$command" != *"git worktree add"* ]] && exit 0

# Parse the worktree path — 4th token after `git worktree add <path>`.
# Strip any branch flags (-b, -B, --detach, etc.) that may appear before the path.
worktree_path=$(echo "$command" \
  | grep -oE 'git worktree add[[:space:]]+[^[:space:]]+' \
  | head -1 \
  | awk '{print $NF}') || exit 0

[ -z "$worktree_path" ] && exit 0

# Resolve relative paths to absolute using the project dir.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
case "$worktree_path" in
  /*) : ;;  # already absolute
  *) worktree_path="$PROJECT_DIR/$worktree_path" ;;
esac

SESSION_UUID="${EITS_SESSION_UUID:-}"
[ -z "$SESSION_UUID" ] && exit 0

EITS_URL="${EITS_URL:-http://localhost:5001/api/v1}"

EITS_API_KEY="${EITS_API_KEY:-}"
auth_header=""
[ -n "$EITS_API_KEY" ] && auth_header="Authorization: Bearer ${EITS_API_KEY}"

curl -sf --max-time 5 \
  -X PATCH "${EITS_URL}/sessions/${SESSION_UUID}" \
  -H "Content-Type: application/json" \
  ${auth_header:+-H "$auth_header"} \
  -d "{\"worktree_path\": \"${worktree_path}\"}" \
  >/dev/null 2>&1 || true

exit 0

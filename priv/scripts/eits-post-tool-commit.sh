#!/usr/bin/env bash
# PostToolUse hook: auto-log git commits made by the agent
# Fires after every Bash tool call; filters for git commit commands.
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ "$tool_name" != "Bash" ] && exit 0

command=$(echo "$input_json" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ "$command" != *"git commit"* ]] && exit 0

# Resolve project dir
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

HASH=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null) || exit 0
MSG=$(git -C "$PROJECT_DIR" log -1 --pretty=%s HEAD 2>/dev/null) || MSG=""

eits commits create --hash "$HASH" --message "$MSG" >/dev/null 2>&1 || true

exit 0

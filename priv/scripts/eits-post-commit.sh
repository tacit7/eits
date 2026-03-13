#!/usr/bin/env bash
# Git post-commit hook: log commit to EITS
# Reads session UUID from .git/eits-session written by startup/resume hooks.
set -uo pipefail

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
SESSION_FILE="$GIT_DIR/eits-session"

[ -f "$SESSION_FILE" ] || exit 0

SESSION_ID=$(cat "$SESSION_FILE" 2>/dev/null | tr -d '[:space:]')
[ -z "$SESSION_ID" ] && exit 0

HASH=$(git rev-parse HEAD 2>/dev/null) || exit 0
MSG=$(git log -1 --pretty=%s HEAD 2>/dev/null) || MSG=""

BASE="${EITS_API_URL:-http://localhost:5001/api/v1}"

curl -sf -X POST "$BASE/commits" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc \
    --arg agent_id "$SESSION_ID" \
    --argjson hashes "[\"$HASH\"]" \
    --argjson messages "[$(jq -Rn --arg m "$MSG" '$m')]" \
    '{agent_id: $agent_id, commit_hashes: $hashes, commit_messages: $messages}')" \
  >/dev/null 2>&1 || true

exit 0

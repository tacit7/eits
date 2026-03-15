#!/usr/bin/env bash
# Git post-commit hook: log commit to EITS
# Reads session UUID from .git/eits-session written by startup/resume hooks.
set -uo pipefail

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
SESSION_FILE="$GIT_DIR/eits-session"
AGENT_FILE="$GIT_DIR/eits-agent"

[ -f "$SESSION_FILE" ] || exit 0

SESSION_ID=$(cat "$SESSION_FILE" 2>/dev/null | tr -d '[:space:]')
[ -z "$SESSION_ID" ] && exit 0

# Use agent UUID if available, fall back to session UUID
AGENT_ID=$(cat "$AGENT_FILE" 2>/dev/null | tr -d '[:space:]')
AGENT_ID="${AGENT_ID:-$SESSION_ID}"

HASH=$(git rev-parse HEAD 2>/dev/null) || exit 0
MSG=$(git log -1 --pretty=%s HEAD 2>/dev/null) || MSG=""

EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}" \
  EITS_AGENT_UUID="$AGENT_ID" \
  eits commits create --hash "$HASH" --message "$MSG" >/dev/null 2>&1 || true

exit 0

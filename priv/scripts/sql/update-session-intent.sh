#!/usr/bin/env bash
# Update session intent field
# Args: $1 = session_uuid, $2 = intent text
set -euo pipefail

session_uuid="${1:-}"
intent="${2:-}"

[ -z "$session_uuid" ] && exit 1

db_path="${EITS_DB_PATH:-$HOME/.config/eye-in-the-sky/eits.db}"

# Escape single quotes for SQLite
intent_escaped="${intent//\'/\'\'}"

sqlite3 "$db_path" \
  "UPDATE sessions SET intent = '$intent_escaped', last_activity_at = datetime('now') WHERE uuid = '$session_uuid';" \
  2>/dev/null || true

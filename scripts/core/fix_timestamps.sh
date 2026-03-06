#!/bin/bash

# Fix bad timestamps in the database
# Converts Go-formatted timestamps to SQLite/Ecto-compatible format
# From: "2025-12-03 08:37:56.916653 -0600 CST m=+..."
# To:   "2025-12-03 08:37:56.916653"

DB_PATH="$HOME/.config/eye-in-the-sky/eits.db"

echo "Fixing bad timestamps in $DB_PATH..."

# Fix agents.last_activity_at
sqlite3 "$DB_PATH" "
UPDATE agents
SET last_activity_at = substr(last_activity_at, 1, 26)
WHERE last_activity_at LIKE '%-%-%:%:%' AND length(last_activity_at) > 26;
"

# Fix agents.completed_at
sqlite3 "$DB_PATH" "
UPDATE agents
SET completed_at = substr(completed_at, 1, 26)
WHERE completed_at LIKE '%-%-%:%:%' AND length(completed_at) > 26;
"

# Fix tasks.created_at
sqlite3 "$DB_PATH" "
UPDATE tasks
SET created_at = substr(created_at, 1, 26)
WHERE created_at LIKE '%-%-%:%:%' AND length(created_at) > 26;
"

# Fix tasks.updated_at
sqlite3 "$DB_PATH" "
UPDATE tasks
SET updated_at = substr(updated_at, 1, 26)
WHERE updated_at LIKE '%-%-%:%:%' AND length(updated_at) > 26;
"

# Fix tasks.completed_at
sqlite3 "$DB_PATH" "
UPDATE tasks
SET completed_at = substr(completed_at, 1, 26)
WHERE completed_at LIKE '%-%-%:%:%' AND length(completed_at) > 26;
"

# Fix task_sessions.created_at
sqlite3 "$DB_PATH" "
UPDATE task_sessions
SET created_at = substr(created_at, 1, 26)
WHERE created_at LIKE '%-%-%:%:%' AND length(created_at) > 26;
"

# Fix task_notes.created_at
sqlite3 "$DB_PATH" "
UPDATE task_notes
SET created_at = substr(created_at, 1, 26)
WHERE created_at LIKE '%-%-%:%:%' AND length(created_at) > 26;
"

# Fix sessions.started_at
sqlite3 "$DB_PATH" "
UPDATE sessions
SET started_at = substr(started_at, 1, 26)
WHERE started_at LIKE '%-%-%:%:%' AND length(started_at) > 26;
"

# Fix sessions.ended_at
sqlite3 "$DB_PATH" "
UPDATE sessions
SET ended_at = substr(ended_at, 1, 26)
WHERE ended_at LIKE '%-%-%:%:%' AND length(ended_at) > 26;
"

# Fix logs.timestamp
sqlite3 "$DB_PATH" "
UPDATE logs
SET timestamp = substr(timestamp, 1, 26)
WHERE timestamp LIKE '%-%-%:%:%' AND length(timestamp) > 26;
"

# Fix notes.created_at
sqlite3 "$DB_PATH" "
UPDATE notes
SET created_at = substr(created_at, 1, 26)
WHERE created_at LIKE '%-%-%:%:%' AND length(created_at) > 26;
"

# Fix projects.created_at
sqlite3 "$DB_PATH" "
UPDATE projects
SET created_at = substr(created_at, 1, 26)
WHERE created_at LIKE '%-%-%:%:%' AND length(created_at) > 26;
"

# Fix projects.updated_at
sqlite3 "$DB_PATH" "
UPDATE projects
SET updated_at = substr(updated_at, 1, 26)
WHERE updated_at LIKE '%-%-%:%:%' AND length(updated_at) > 26;
"

echo "Done! All timestamps fixed."
echo "Format: YYYY-MM-DD HH:MM:SS.microseconds"

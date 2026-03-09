#!/usr/bin/env python3
"""
Migrate data from SQLite eits.db to PostgreSQL eits_dev.

Handles:
- Column intersection (skips SQLite-only columns not in Postgres schema)
- Truncates Postgres tables before import (clean slate)
- SQLite integer booleans (0/1) -> Python bool for boolean columns
- messages.metadata JSON string -> jsonb via Json() wrapper
- oban_jobs JSON array strings -> proper Python lists
- logs/session_context UUID session_ids -> integer via lookup
- FK constraints disabled during migration
- Sequence reset after bulk inserts
"""

import sqlite3
import psycopg2
import psycopg2.extras
from psycopg2.extras import Json
import json
import sys

SQLITE_PATH = "/Users/urielmaldonado/.config/eye-in-the-sky/eits.db"
PG_DSN = "dbname=eits_dev user=postgres host=localhost"

# Tables in migration order (respects FK dependencies)
TABLES = [
    "workflow_states",
    "projects",
    "tags",
    "agents",
    "sessions",
    "tasks",
    "task_sessions",
    "task_tags",
    "channels",
    "channel_members",
    "messages",
    "message_reactions",
    "file_attachments",
    "commits",
    "commit_tasks",
    "notes",
    "subagent_prompts",
    "bookmarks",
    "logs",
    "session_logs",
    "scheduled_jobs",
    "job_runs",
    "session_context",
    "session_metrics",
    "meta",
    # oban_jobs skipped: completed/discarded historical jobs, complex array types not worth migrating
]

# Truncate in reverse FK order (dependents first)
TRUNCATE_ORDER = list(reversed(TABLES))

# jsonb columns: value must be wrapped in Json()
JSONB_COLUMNS = {
    "messages": {"metadata"},
}

# Boolean columns (SQLite stores as 0/1 integer)
BOOL_COLUMNS = {
    "projects": {"active"},
    "agents": {"bookmarked"},
    "tasks": {"archived"},
    "subagent_prompts": {"active"},
}

# Tables with ON CONFLICT DO NOTHING (handle duplicates gracefully)
UPSERT_SKIP = {"commits"}

# Columns where SQLite may store UUIDs but Postgres expects integer FK
# We'll resolve UUID -> int at runtime using the sessions table
UUID_SESSION_ID_TABLES = {"logs", "session_context"}


def get_sqlite_columns(sqlite_cur, table):
    sqlite_cur.execute(f"PRAGMA table_info({table})")
    return [row[1] for row in sqlite_cur.fetchall()]


def get_pg_columns(pg_cur, table):
    pg_cur.execute("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = %s
        ORDER BY ordinal_position
    """, (table,))
    return [row[0] for row in pg_cur.fetchall()]


def get_pg_sequences(pg_cur):
    pg_cur.execute("""
        SELECT table_name, pg_get_serial_sequence(table_name, column_name) as seq
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_default LIKE 'nextval%'
          AND column_name = 'id'
    """)
    return {row[0]: row[1] for row in pg_cur.fetchall() if row[1]}


def build_uuid_to_id_map(sqlite_cur):
    """Build a UUID -> integer ID map from the SQLite sessions table."""
    sqlite_cur.execute("SELECT uuid, id FROM sessions WHERE uuid IS NOT NULL")
    return {row[0]: row[1] for row in sqlite_cur.fetchall()}


def coerce_value(value, table, col, uuid_to_id=None):
    if value is None:
        return None

    # Boolean cast
    if table in BOOL_COLUMNS and col in BOOL_COLUMNS[table]:
        return bool(value)

    # jsonb
    if table in JSONB_COLUMNS and col in JSONB_COLUMNS[table]:
        if isinstance(value, str):
            try:
                return Json(json.loads(value))
            except (json.JSONDecodeError, ValueError):
                return Json({})
        if isinstance(value, dict):
            return Json(value)
        return Json({})

    # UUID -> int for session_id in certain tables
    if table in UUID_SESSION_ID_TABLES and col == "session_id" and uuid_to_id is not None:
        if isinstance(value, str) and "-" in value:
            # It's a UUID - look up the integer ID
            return uuid_to_id.get(value)
        return value

    return value


def migrate_table(sqlite_cur, pg_cur, table, uuid_to_id=None):
    sqlite_cols = get_sqlite_columns(sqlite_cur, table)
    pg_cols = get_pg_columns(pg_cur, table)

    common_cols = [c for c in pg_cols if c in sqlite_cols]

    if not common_cols:
        print(f"  [SKIP] {table}: no common columns")
        return 0

    col_list = ", ".join(common_cols)
    placeholders = ", ".join(["%s"] * len(common_cols))

    if table in UPSERT_SKIP:
        insert_sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT DO NOTHING"
    else:
        insert_sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders})"

    sqlite_cur.execute(f"SELECT {col_list} FROM {table}")
    rows = sqlite_cur.fetchall()

    if not rows:
        print(f"  [EMPTY] {table}")
        return 0

    coerced_rows = [
        tuple(coerce_value(val, table, col, uuid_to_id) for val, col in zip(row, common_cols))
        for row in rows
    ]

    psycopg2.extras.execute_batch(pg_cur, insert_sql, coerced_rows, page_size=500)
    print(f"  [OK] {table}: {len(coerced_rows)} rows")
    return len(coerced_rows)


def reset_sequences(pg_cur, sequences):
    for table, seq in sequences.items():
        pg_cur.execute(f"SELECT COALESCE(MAX(id), 0) FROM {table}")
        max_id = pg_cur.fetchone()[0]
        if max_id > 0:
            pg_cur.execute("SELECT setval(%s, %s)", (seq, max_id))
            print(f"  [SEQ] {table}: reset to {max_id}")


def main():
    print("Connecting to databases...")
    sqlite_conn = sqlite3.connect(SQLITE_PATH)
    sqlite_cur = sqlite_conn.cursor()

    pg_conn = psycopg2.connect(PG_DSN)
    pg_conn.autocommit = False
    pg_cur = pg_conn.cursor()

    print("Disabling FK constraints...")
    pg_cur.execute("SET session_replication_role = replica")

    print("Truncating Postgres tables (clean slate)...")
    for table in TRUNCATE_ORDER:
        pg_cur.execute(f"TRUNCATE TABLE {table} RESTART IDENTITY CASCADE")
    print("  Done.")

    print("Building UUID -> ID map for session lookups...")
    uuid_to_id = build_uuid_to_id_map(sqlite_cur)

    total = 0
    errors = []

    for table in TABLES:
        try:
            count = migrate_table(sqlite_cur, pg_cur, table, uuid_to_id)
            total += count
        except Exception as e:
            errors.append((table, str(e)))
            print(f"  [ERR] {table}: {e}")
            pg_conn.rollback()
            pg_cur.execute("SET session_replication_role = replica")

    print("\nResetting sequences...")
    sequences = get_pg_sequences(pg_cur)
    reset_sequences(pg_cur, sequences)

    print("\nRe-enabling FK constraints...")
    pg_cur.execute("SET session_replication_role = DEFAULT")

    if errors:
        print(f"\n{len(errors)} table(s) failed:")
        for table, err in errors:
            print(f"  - {table}: {err}")
        sys.exit(1)

    pg_conn.commit()
    print(f"\nDone. Migrated {total} rows total.")

    sqlite_conn.close()
    pg_conn.close()


if __name__ == "__main__":
    main()

-- ============================================================================
-- UUID-to-Integer PK Migration for eits.db
-- ============================================================================
-- Converts TEXT UUID primary keys to INTEGER AUTOINCREMENT PKs.
-- UUIDs are preserved in a `uuid TEXT NOT NULL UNIQUE` column.
-- Projects and workflow_states already have integer PKs; they are untouched.
--
-- IMPORTANT: Back up eits.db before running this script.
--   cp ~/.config/eye-in-the-sky/eits.db ~/.config/eye-in-the-sky/eits.db.bak
--
-- Run with:
--   sqlite3 ~/.config/eye-in-the-sky/eits.db < migration_uuid_to_int.sql
-- ============================================================================

PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;

-- ============================================================================
-- PHASE 0: Save cross-reference UUID values that would be lost during rebuild
-- ============================================================================

-- Save agents' session_id, parent_agent_id, parent_session_id (all TEXT UUIDs)
CREATE TEMPORARY TABLE _agents_refs (
    agent_uuid TEXT PRIMARY KEY,
    session_uuid TEXT,
    parent_agent_uuid TEXT,
    parent_session_uuid TEXT
);

INSERT INTO _agents_refs (agent_uuid, session_uuid, parent_agent_uuid, parent_session_uuid)
SELECT id, session_id, parent_agent_id, parent_session_id
FROM agents;

-- Save messages' parent_message_id (TEXT UUID self-reference)
CREATE TEMPORARY TABLE _messages_parent_refs (
    message_uuid TEXT PRIMARY KEY,
    parent_message_uuid TEXT
);

INSERT INTO _messages_parent_refs (message_uuid, parent_message_uuid)
SELECT id, parent_message_id
FROM messages
WHERE parent_message_id IS NOT NULL;


-- ============================================================================
-- PHASE 1: Core tables (rebuild with INTEGER PK + uuid column)
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. agents (no UUID FK deps; projects.id already integer)
-- --------------------------------------------------------------------------
CREATE TABLE agents_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    persona_id TEXT,
    project_id INTEGER,
    description TEXT,
    source TEXT DEFAULT 'worktree',
    bookmarked INTEGER DEFAULT 0,
    created_at TEXT,
    archived_at TEXT,
    status TEXT DEFAULT 'idle',
    git_worktree_path TEXT,
    feature_description TEXT,
    current_task TEXT,
    last_activity_at TIMESTAMP,
    window_id TEXT,
    project_name TEXT,
    session_id INTEGER,
    terminal_application TEXT,
    parent_agent_id INTEGER,
    parent_session_id INTEGER,
    completed_at DATETIME,
    updated_at TEXT
);

-- Insert with cross-ref columns set to NULL; resolved in Phase 5
INSERT INTO agents_new (uuid, persona_id, project_id, description, source, bookmarked,
    created_at, archived_at, status, git_worktree_path, feature_description, current_task,
    last_activity_at, window_id, project_name, session_id, terminal_application,
    parent_agent_id, parent_session_id, completed_at, updated_at)
SELECT id, persona_id, project_id, description, source, bookmarked,
    created_at, archived_at, status, git_worktree_path, feature_description, current_task,
    last_activity_at, window_id, project_name, NULL, terminal_application,
    NULL, NULL, completed_at, updated_at
FROM agents;

DROP TABLE agents;
ALTER TABLE agents_new RENAME TO agents;

-- --------------------------------------------------------------------------
-- 2. sessions (FK agent_id resolved via JOIN on agents.uuid)
-- --------------------------------------------------------------------------
CREATE TABLE sessions_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    agent_id INTEGER NOT NULL,
    name TEXT,
    status TEXT DEFAULT 'active',
    intent TEXT,
    claude_session_id TEXT,
    provider TEXT DEFAULT 'claude',
    model TEXT,
    project_id INTEGER,
    git_worktree_path TEXT,
    started_at TEXT NOT NULL,
    last_activity_at TEXT,
    ended_at TEXT,
    archived_at TEXT,
    model_provider TEXT,
    model_name TEXT,
    model_version TEXT,
    description TEXT,
    FOREIGN KEY (agent_id) REFERENCES agents(id),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

INSERT INTO sessions_new (uuid, agent_id, name, status, intent, claude_session_id,
    provider, model, project_id, git_worktree_path, started_at, last_activity_at,
    ended_at, archived_at, model_provider, model_name, model_version, description)
SELECT s.id, a.id, s.name, s.status, s.intent, s.claude_session_id,
    s.provider, s.model, s.project_id, s.git_worktree_path, s.started_at,
    s.last_activity_at, s.ended_at, s.archived_at, s.model_provider,
    s.model_name, s.model_version, s.description
FROM sessions s
JOIN agents a ON a.uuid = s.agent_id;

DROP TABLE sessions;
ALTER TABLE sessions_new RENAME TO sessions;

-- --------------------------------------------------------------------------
-- 3. tasks (FK agent_id resolved via JOIN; project_id becomes INTEGER)
--    Removes the old int_id column.
-- --------------------------------------------------------------------------
CREATE TABLE tasks_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    description TEXT,
    state_id INTEGER,
    project_id INTEGER,
    priority INTEGER DEFAULT 0,
    due_at TEXT,
    completed_at TEXT,
    agent_id INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT,
    archived INTEGER DEFAULT 0,
    FOREIGN KEY (state_id) REFERENCES workflow_states(id),
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO tasks_new (uuid, title, description, state_id, project_id, priority,
    due_at, completed_at, agent_id, created_at, updated_at, archived)
SELECT t.id, t.title, t.description, t.state_id, CAST(t.project_id AS INTEGER),
    t.priority, t.due_at, t.completed_at, a.id, t.created_at, t.updated_at, t.archived
FROM tasks t
LEFT JOIN agents a ON a.uuid = t.agent_id;

DROP TABLE tasks;
ALTER TABLE tasks_new RENAME TO tasks;

-- --------------------------------------------------------------------------
-- 4. channels (project_id already integer; created_by_session_id resolved)
-- --------------------------------------------------------------------------
CREATE TABLE channels_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    channel_type TEXT DEFAULT 'public' NOT NULL,
    project_id INTEGER,
    created_by_session_id INTEGER,
    archived_at TEXT,
    inserted_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

INSERT INTO channels_new (uuid, name, description, channel_type, project_id,
    created_by_session_id, archived_at, inserted_at, updated_at)
SELECT c.id, c.name, c.description, c.channel_type, c.project_id,
    s.id, c.archived_at, c.inserted_at, c.updated_at
FROM channels c
LEFT JOIN sessions s ON s.uuid = c.created_by_session_id;

DROP TABLE channels;
ALTER TABLE channels_new RENAME TO channels;

-- --------------------------------------------------------------------------
-- 5. messages (session_id, channel_id via JOIN; self-ref parent_message_id
--    resolved from temp table _messages_parent_refs)
-- --------------------------------------------------------------------------
CREATE TABLE messages_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    project_id INTEGER,
    session_id INTEGER,
    sender_role TEXT NOT NULL,
    recipient_role TEXT,
    provider TEXT,
    provider_session_id TEXT,
    direction TEXT NOT NULL,
    body TEXT NOT NULL,
    status TEXT DEFAULT 'sent' NOT NULL,
    metadata TEXT DEFAULT '{}',
    inserted_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    channel_id INTEGER,
    parent_message_id INTEGER,
    thread_reply_count INTEGER DEFAULT 0,
    last_thread_reply_at TEXT,
    source_uuid TEXT,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE,
    FOREIGN KEY (parent_message_id) REFERENCES messages(id) ON DELETE CASCADE
);

-- Insert all messages with session_id and channel_id resolved; parent_message_id NULL initially
INSERT INTO messages_new (uuid, project_id, session_id, sender_role, recipient_role,
    provider, provider_session_id, direction, body, status, metadata,
    inserted_at, updated_at, channel_id, parent_message_id,
    thread_reply_count, last_thread_reply_at, source_uuid)
SELECT m.id, m.project_id,
    s.id,
    m.sender_role, m.recipient_role, m.provider, m.provider_session_id,
    m.direction, m.body, m.status, m.metadata,
    m.inserted_at, m.updated_at,
    ch.id,
    NULL,
    m.thread_reply_count, m.last_thread_reply_at, m.source_uuid
FROM messages m
LEFT JOIN sessions s ON s.uuid = m.session_id
LEFT JOIN channels ch ON ch.uuid = m.channel_id;

DROP TABLE messages;
ALTER TABLE messages_new RENAME TO messages;

-- Resolve self-referencing parent_message_id from saved refs
UPDATE messages
SET parent_message_id = (
    SELECT mn_parent.id
    FROM messages mn_parent
    WHERE mn_parent.uuid = (
        SELECT pr.parent_message_uuid
        FROM _messages_parent_refs pr
        WHERE pr.message_uuid = messages.uuid
    )
)
WHERE EXISTS (
    SELECT 1 FROM _messages_parent_refs pr
    WHERE pr.message_uuid = messages.uuid
);

-- --------------------------------------------------------------------------
-- 6. notes (polymorphic parent_id; resolve after all parent tables exist)
-- --------------------------------------------------------------------------
CREATE TABLE notes_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    parent_id TEXT NOT NULL,
    parent_type TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    title TEXT,
    starred INTEGER DEFAULT 0
);

-- Some notes have empty-string IDs; generate UUIDs for those
INSERT INTO notes_new (uuid, parent_id, parent_type, body, created_at, title, starred)
SELECT
    CASE WHEN id IS NULL OR id = '' THEN
        lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
        substr(lower(hex(randomblob(2))),2) || '-' ||
        substr('89ab', abs(random()) % 4 + 1, 1) ||
        substr(lower(hex(randomblob(2))),2) || '-' ||
        lower(hex(randomblob(6)))
    ELSE id END,
    parent_id, parent_type, body, created_at, title, starred
FROM notes;

DROP TABLE notes;
ALTER TABLE notes_new RENAME TO notes;

-- Resolve polymorphic parent_id references:
-- parent_type = 'sessions' -> parent_id was a session UUID
UPDATE notes SET parent_id = CAST((
    SELECT s.id FROM sessions s WHERE s.uuid = notes.parent_id
) AS TEXT)
WHERE parent_type = 'sessions'
AND EXISTS (SELECT 1 FROM sessions s WHERE s.uuid = notes.parent_id);

-- parent_type = 'session' (variant spelling)
UPDATE notes SET parent_id = CAST((
    SELECT s.id FROM sessions s WHERE s.uuid = notes.parent_id
) AS TEXT)
WHERE parent_type = 'session'
AND EXISTS (SELECT 1 FROM sessions s WHERE s.uuid = notes.parent_id);

-- parent_type = 'agents' -> parent_id was an agent UUID
UPDATE notes SET parent_id = CAST((
    SELECT a.id FROM agents a WHERE a.uuid = notes.parent_id
) AS TEXT)
WHERE parent_type = 'agents'
AND EXISTS (SELECT 1 FROM agents a WHERE a.uuid = notes.parent_id);

-- parent_type = 'tasks' -> parent_id was a task UUID
UPDATE notes SET parent_id = CAST((
    SELECT t.id FROM tasks t WHERE t.uuid = notes.parent_id
) AS TEXT)
WHERE parent_type = 'tasks'
AND EXISTS (SELECT 1 FROM tasks t WHERE t.uuid = notes.parent_id);

-- parent_type = 'projects' -> parent_id is already integer; no update needed


-- ============================================================================
-- PHASE 2: Leaf tables (rebuild with INTEGER PK + uuid column)
-- ============================================================================

-- --------------------------------------------------------------------------
-- 7a. subagent_prompts
-- --------------------------------------------------------------------------
CREATE TABLE subagent_prompts_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    description TEXT,
    prompt_text TEXT NOT NULL,
    project_id INTEGER,
    active BOOLEAN DEFAULT 1,
    version INTEGER DEFAULT 1,
    tags TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    CHECK (slug GLOB '[a-z][a-z0-9-]*')
);

INSERT INTO subagent_prompts_new (uuid, name, slug, description, prompt_text,
    project_id, active, version, tags, created_at, updated_at, created_by)
SELECT id, name, slug, description, prompt_text,
    CAST(project_id AS INTEGER), active, version, tags, created_at, updated_at, created_by
FROM subagent_prompts;

DROP TABLE subagent_prompts;
ALTER TABLE subagent_prompts_new RENAME TO subagent_prompts;

-- --------------------------------------------------------------------------
-- 7b. personas
-- --------------------------------------------------------------------------
CREATE TABLE personas_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    expertise TEXT NOT NULL,
    initial_context TEXT NOT NULL,
    preferred_tools TEXT,
    specialization TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO personas_new (uuid, name, description, expertise, initial_context,
    preferred_tools, specialization, created_at, updated_at)
SELECT id, name, description, expertise, initial_context,
    preferred_tools, specialization, created_at, updated_at
FROM personas;

DROP TABLE personas;
ALTER TABLE personas_new RENAME TO personas;

-- --------------------------------------------------------------------------
-- 7c. action_plans
-- --------------------------------------------------------------------------
CREATE TABLE action_plans_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    session_id INTEGER NOT NULL,
    agent_id INTEGER NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(id),
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO action_plans_new (uuid, session_id, agent_id, content, created_at)
SELECT ap.id, s.id, a.id, ap.content, ap.created_at
FROM action_plans ap
JOIN sessions s ON s.uuid = ap.session_id
JOIN agents a ON a.uuid = ap.agent_id;

DROP TABLE action_plans;
ALTER TABLE action_plans_new RENAME TO action_plans;

-- --------------------------------------------------------------------------
-- 7d. bookmarks
-- --------------------------------------------------------------------------
CREATE TABLE bookmarks_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    bookmark_type TEXT NOT NULL,
    bookmark_id TEXT,
    file_path TEXT,
    line_number INTEGER,
    url TEXT,
    title TEXT,
    description TEXT,
    category TEXT,
    priority INTEGER DEFAULT 0,
    position INTEGER,
    project_id INTEGER,
    agent_id INTEGER,
    accessed_at TEXT,
    inserted_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

INSERT INTO bookmarks_new (uuid, bookmark_type, bookmark_id, file_path, line_number,
    url, title, description, category, priority, position, project_id,
    agent_id, accessed_at, inserted_at, updated_at)
SELECT b.id, b.bookmark_type, b.bookmark_id, b.file_path, b.line_number,
    b.url, b.title, b.description, b.category, b.priority, b.position, b.project_id,
    a.id, b.accessed_at, b.inserted_at, b.updated_at
FROM bookmarks b
LEFT JOIN agents a ON a.uuid = b.agent_id;

DROP TABLE bookmarks;
ALTER TABLE bookmarks_new RENAME TO bookmarks;

-- --------------------------------------------------------------------------
-- 7e. prompts (standalone, TEXT PK -> INTEGER PK)
-- --------------------------------------------------------------------------
CREATE TABLE prompts_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    prompt TEXT NOT NULL,
    liked BOOLEAN DEFAULT 0,
    imported_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO prompts_new (uuid, name, description, prompt, liked, imported_at)
SELECT id, name, description, prompt, liked, imported_at
FROM prompts;

DROP TABLE prompts;
ALTER TABLE prompts_new RENAME TO prompts;

-- --------------------------------------------------------------------------
-- 8a. channel_members
-- --------------------------------------------------------------------------
CREATE TABLE channel_members_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    channel_id INTEGER NOT NULL,
    agent_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    role TEXT DEFAULT 'member' NOT NULL,
    joined_at TEXT NOT NULL,
    last_read_at TEXT,
    notifications TEXT DEFAULT 'all' NOT NULL,
    inserted_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE,
    FOREIGN KEY (agent_id) REFERENCES agents(id),
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

INSERT INTO channel_members_new (uuid, channel_id, agent_id, session_id, role,
    joined_at, last_read_at, notifications, inserted_at, updated_at)
SELECT cm.id, ch.id, a.id, s.id,
    cm.role, cm.joined_at, cm.last_read_at, cm.notifications,
    cm.inserted_at, cm.updated_at
FROM channel_members cm
JOIN channels ch ON ch.uuid = cm.channel_id
JOIN agents a ON a.uuid = cm.agent_id
JOIN sessions s ON s.uuid = cm.session_id;

DROP TABLE channel_members;
ALTER TABLE channel_members_new RENAME TO channel_members;

-- --------------------------------------------------------------------------
-- 8b. message_reactions
-- --------------------------------------------------------------------------
CREATE TABLE message_reactions_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    message_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    emoji TEXT NOT NULL,
    inserted_at TEXT NOT NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

INSERT INTO message_reactions_new (uuid, message_id, session_id, emoji, inserted_at)
SELECT mr.id, mn.id, s.id, mr.emoji, mr.inserted_at
FROM message_reactions mr
JOIN messages mn ON mn.uuid = mr.message_id
JOIN sessions s ON s.uuid = mr.session_id;

DROP TABLE message_reactions;
ALTER TABLE message_reactions_new RENAME TO message_reactions;

-- --------------------------------------------------------------------------
-- 8c. file_attachments
-- --------------------------------------------------------------------------
CREATE TABLE file_attachments_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    message_id INTEGER NOT NULL,
    filename TEXT NOT NULL,
    original_filename TEXT NOT NULL,
    content_type TEXT,
    size_bytes INTEGER,
    storage_path TEXT NOT NULL,
    upload_session_id INTEGER,
    inserted_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

INSERT INTO file_attachments_new (uuid, message_id, filename, original_filename,
    content_type, size_bytes, storage_path, upload_session_id, inserted_at, updated_at)
SELECT fa.id, mn.id, fa.filename, fa.original_filename, fa.content_type, fa.size_bytes,
    fa.storage_path, s.id, fa.inserted_at, fa.updated_at
FROM file_attachments fa
JOIN messages mn ON mn.uuid = fa.message_id
LEFT JOIN sessions s ON s.uuid = fa.upload_session_id;

DROP TABLE file_attachments;
ALTER TABLE file_attachments_new RENAME TO file_attachments;


-- ============================================================================
-- PHASE 3: Join tables (rebuild with integer FKs)
-- ============================================================================

-- --------------------------------------------------------------------------
-- 9a. task_sessions
-- --------------------------------------------------------------------------
CREATE TABLE task_sessions_new (
    task_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (task_id, session_id),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

INSERT INTO task_sessions_new (task_id, session_id, created_at)
SELECT t.id, s.id, ts.created_at
FROM task_sessions ts
JOIN tasks t ON t.uuid = ts.task_id
JOIN sessions s ON s.uuid = ts.session_id;

DROP TABLE task_sessions;
ALTER TABLE task_sessions_new RENAME TO task_sessions;

-- --------------------------------------------------------------------------
-- 9b. task_tags (task_id was UUID TEXT, tag_id already INTEGER)
-- --------------------------------------------------------------------------
CREATE TABLE task_tags_new (
    task_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (task_id, tag_id),
    FOREIGN KEY (task_id) REFERENCES tasks(id),
    FOREIGN KEY (tag_id) REFERENCES tags(id)
);

INSERT INTO task_tags_new (task_id, tag_id)
SELECT t.id, tt.tag_id
FROM task_tags tt
JOIN tasks t ON t.uuid = tt.task_id;

DROP TABLE task_tags;
ALTER TABLE task_tags_new RENAME TO task_tags;

-- --------------------------------------------------------------------------
-- 9c. commit_tasks (commit_id already INTEGER, task_id was UUID TEXT)
-- --------------------------------------------------------------------------
CREATE TABLE commit_tasks_new (
    commit_id INTEGER NOT NULL,
    task_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (commit_id, task_id),
    FOREIGN KEY (commit_id) REFERENCES commits(id) ON DELETE CASCADE,
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

INSERT INTO commit_tasks_new (commit_id, task_id, created_at)
SELECT ct.commit_id, t.id, ct.created_at
FROM commit_tasks ct
JOIN tasks t ON t.uuid = ct.task_id;

DROP TABLE commit_tasks;
ALTER TABLE commit_tasks_new RENAME TO commit_tasks;


-- ============================================================================
-- PHASE 4: Rebuild already-integer-PK tables that have TEXT UUID FK columns
-- ============================================================================

-- --------------------------------------------------------------------------
-- 10a. commits (agent_id TEXT, session_id TEXT, project_id TEXT)
-- --------------------------------------------------------------------------
CREATE TABLE commits_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER,
    commit_hash TEXT NOT NULL,
    commit_message TEXT,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    project_id INTEGER REFERENCES projects(id),
    session_id INTEGER REFERENCES sessions(id),
    created_at TEXT,
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO commits_new (id, agent_id, commit_hash, commit_message, timestamp,
    project_id, session_id, created_at)
SELECT c.id, a.id, c.commit_hash, c.commit_message, c.timestamp,
    CAST(c.project_id AS INTEGER), s.id, c.created_at
FROM commits c
LEFT JOIN agents a ON a.uuid = c.agent_id
LEFT JOIN sessions s ON s.uuid = c.session_id;

DROP TABLE commits;
ALTER TABLE commits_new RENAME TO commits;

-- --------------------------------------------------------------------------
-- 10b. logs (session_id TEXT UUID)
-- --------------------------------------------------------------------------
CREATE TABLE logs_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    type TEXT NOT NULL,
    message TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

INSERT INTO logs_new (id, session_id, type, message, timestamp)
SELECT l.id, s.id, l.type, l.message, l.timestamp
FROM logs l
JOIN sessions s ON s.uuid = l.session_id;

DROP TABLE logs;
ALTER TABLE logs_new RENAME TO logs;

-- --------------------------------------------------------------------------
-- 10c. context (session_id TEXT UUID)
-- --------------------------------------------------------------------------
CREATE TABLE context_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    UNIQUE(session_id, key),
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

INSERT INTO context_new (id, session_id, key, value)
SELECT c.id, s.id, c.key, c.value
FROM context c
JOIN sessions s ON s.uuid = c.session_id;

DROP TABLE context;
ALTER TABLE context_new RENAME TO context;

-- --------------------------------------------------------------------------
-- 10d. session_context (agent_id TEXT, session_id TEXT)
-- --------------------------------------------------------------------------
CREATE TABLE session_context_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    context TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO session_context_new (id, agent_id, session_id, context, created_at, updated_at)
SELECT sc.id, a.id, s.id, sc.context, sc.created_at, sc.updated_at
FROM session_context sc
JOIN agents a ON a.uuid = sc.agent_id
JOIN sessions s ON s.uuid = sc.session_id;

DROP TABLE session_context;
ALTER TABLE session_context_new RENAME TO session_context;

-- --------------------------------------------------------------------------
-- 10e. session_logs (agent_id TEXT UUID)
-- --------------------------------------------------------------------------
CREATE TABLE session_logs_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER NOT NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    log_level TEXT NOT NULL,
    category TEXT NOT NULL,
    message TEXT NOT NULL,
    details TEXT,
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO session_logs_new (id, agent_id, timestamp, log_level, category, message, details)
SELECT sl.id, a.id, sl.timestamp, sl.log_level, sl.category, sl.message, sl.details
FROM session_logs sl
JOIN agents a ON a.uuid = sl.agent_id;

DROP TABLE session_logs;
ALTER TABLE session_logs_new RENAME TO session_logs;

-- --------------------------------------------------------------------------
-- 10f. session_notes (agent_id TEXT UUID)
-- --------------------------------------------------------------------------
CREATE TABLE session_notes_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER NOT NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    note_type TEXT NOT NULL,
    content TEXT NOT NULL,
    priority TEXT NOT NULL,
    tags TEXT,
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO session_notes_new (id, agent_id, timestamp, note_type, content, priority, tags)
SELECT sn.id, a.id, sn.timestamp, sn.note_type, sn.content, sn.priority, sn.tags
FROM session_notes sn
JOIN agents a ON a.uuid = sn.agent_id;

DROP TABLE session_notes;
ALTER TABLE session_notes_new RENAME TO session_notes;

-- --------------------------------------------------------------------------
-- 10g. session_metrics (agent_id TEXT, session_id TEXT)
-- --------------------------------------------------------------------------
CREATE TABLE session_metrics_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER NOT NULL,
    session_id INTEGER,
    tokens_used INTEGER NOT NULL,
    tokens_budget INTEGER NOT NULL,
    tokens_remaining INTEGER NOT NULL,
    input_tokens INTEGER,
    output_tokens INTEGER,
    estimated_cost_usd REAL,
    model_name TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE
);

INSERT INTO session_metrics_new (id, agent_id, session_id, tokens_used, tokens_budget,
    tokens_remaining, input_tokens, output_tokens, estimated_cost_usd, model_name,
    timestamp, notes, created_at)
SELECT sm.id, a.id, s.id, sm.tokens_used, sm.tokens_budget, sm.tokens_remaining,
    sm.input_tokens, sm.output_tokens, sm.estimated_cost_usd, sm.model_name,
    sm.timestamp, sm.notes, sm.created_at
FROM session_metrics sm
JOIN agents a ON a.uuid = sm.agent_id
LEFT JOIN sessions s ON s.uuid = sm.session_id;

DROP TABLE session_metrics;
ALTER TABLE session_metrics_new RENAME TO session_metrics;

-- --------------------------------------------------------------------------
-- 10h. compactions (agent_id TEXT, old_session_id TEXT, new_session_id TEXT)
-- --------------------------------------------------------------------------
CREATE TABLE compactions_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER NOT NULL,
    old_session_id INTEGER,
    new_session_id INTEGER NOT NULL,
    compacted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    summary TEXT,
    jsonl_file_path TEXT,
    jsonl_file_size INTEGER,
    message_count INTEGER,
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO compactions_new (id, agent_id, old_session_id, new_session_id,
    compacted_at, summary, jsonl_file_path, jsonl_file_size, message_count)
SELECT co.id, a.id, sold.id, snew.id,
    co.compacted_at, co.summary, co.jsonl_file_path, co.jsonl_file_size, co.message_count
FROM compactions co
JOIN agents a ON a.uuid = co.agent_id
LEFT JOIN sessions sold ON sold.uuid = co.old_session_id
JOIN sessions snew ON snew.uuid = co.new_session_id;

DROP TABLE compactions;
ALTER TABLE compactions_new RENAME TO compactions;

-- --------------------------------------------------------------------------
-- 10i. actions (agent_id TEXT UUID)
-- --------------------------------------------------------------------------
CREATE TABLE actions_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER NOT NULL,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    action_type TEXT NOT NULL,
    description TEXT NOT NULL,
    details TEXT,
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

INSERT INTO actions_new (id, agent_id, timestamp, action_type, description, details)
SELECT ac.id, a.id, ac.timestamp, ac.action_type, ac.description, ac.details
FROM actions ac
JOIN agents a ON a.uuid = ac.agent_id;

DROP TABLE actions;
ALTER TABLE actions_new RENAME TO actions;

-- --------------------------------------------------------------------------
-- 10j. task_events (task_id TEXT UUID)
-- --------------------------------------------------------------------------
CREATE TABLE task_events_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER,
    event_type TEXT,
    payload TEXT,
    actor TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

INSERT INTO task_events_new (id, task_id, event_type, payload, actor, created_at)
SELECT te.id, t.id, te.event_type, te.payload, te.actor, te.created_at
FROM task_events te
LEFT JOIN tasks t ON t.uuid = te.task_id;

DROP TABLE task_events;
ALTER TABLE task_events_new RENAME TO task_events;

-- --------------------------------------------------------------------------
-- 10k. task_notes (task_id TEXT UUID)
-- --------------------------------------------------------------------------
CREATE TABLE task_notes_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER,
    author TEXT,
    body TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

INSERT INTO task_notes_new (id, task_id, author, body, created_at)
SELECT tn.id, t.id, tn.author, tn.body, tn.created_at
FROM task_notes tn
LEFT JOIN tasks t ON t.uuid = tn.task_id;

DROP TABLE task_notes;
ALTER TABLE task_notes_new RENAME TO task_notes;


-- ============================================================================
-- PHASE 5: Deferred cross-references on agents
-- ============================================================================
-- Resolve agents.session_id, agents.parent_agent_id, agents.parent_session_id
-- using the saved UUID values from _agents_refs temp table.

UPDATE agents SET session_id = (
    SELECT s.id FROM sessions s
    JOIN _agents_refs ar ON ar.agent_uuid = agents.uuid
    WHERE s.uuid = ar.session_uuid
)
WHERE EXISTS (
    SELECT 1 FROM _agents_refs ar
    WHERE ar.agent_uuid = agents.uuid AND ar.session_uuid IS NOT NULL
);

UPDATE agents SET parent_agent_id = (
    SELECT pa.id FROM agents pa
    JOIN _agents_refs ar ON ar.agent_uuid = agents.uuid
    WHERE pa.uuid = ar.parent_agent_uuid
)
WHERE EXISTS (
    SELECT 1 FROM _agents_refs ar
    WHERE ar.agent_uuid = agents.uuid AND ar.parent_agent_uuid IS NOT NULL
);

UPDATE agents SET parent_session_id = (
    SELECT ps.id FROM sessions ps
    JOIN _agents_refs ar ON ar.agent_uuid = agents.uuid
    WHERE ps.uuid = ar.parent_session_uuid
)
WHERE EXISTS (
    SELECT 1 FROM _agents_refs ar
    WHERE ar.agent_uuid = agents.uuid AND ar.parent_session_uuid IS NOT NULL
);

-- Clean up temp tables
DROP TABLE IF EXISTS _agents_refs;
DROP TABLE IF EXISTS _messages_parent_refs;


-- ============================================================================
-- PHASE 6: FTS5 rebuild
-- ============================================================================

-- Drop existing FTS triggers (may already be gone from table drops, but be safe)
DROP TRIGGER IF EXISTS sessions_fts_insert;
DROP TRIGGER IF EXISTS sessions_fts_update;
DROP TRIGGER IF EXISTS sessions_fts_delete;
DROP TRIGGER IF EXISTS task_search_insert;
DROP TRIGGER IF EXISTS task_search_update;
DROP TRIGGER IF EXISTS task_search_delete;

-- Drop existing FTS tables
DROP TABLE IF EXISTS sessions_fts;
DROP TABLE IF EXISTS task_search;

-- Recreate FTS5 tables
CREATE VIRTUAL TABLE sessions_fts USING fts5(
    session_id UNINDEXED,
    session_name,
    description,
    agent_id UNINDEXED,
    agent_description,
    project_name
);

CREATE VIRTUAL TABLE task_search USING fts5(
    task_id UNINDEXED,
    title,
    description,
    tokenize='porter'
);

-- Repopulate sessions_fts
-- rowid = sessions.id (integer PK); session_id stores uuid for lookups
INSERT INTO sessions_fts (rowid, session_id, session_name, description, agent_id, agent_description, project_name)
SELECT
    s.id,
    s.uuid,
    COALESCE(s.name, ''),
    COALESCE(s.description, ''),
    CAST(s.agent_id AS TEXT),
    COALESCE(a.description, ''),
    COALESCE(p.name, '')
FROM sessions s
LEFT JOIN agents a ON a.id = s.agent_id
LEFT JOIN projects p ON p.id = s.project_id;

-- Repopulate task_search
-- task_id stores CAST(integer PK AS TEXT) for join_key compatibility
INSERT INTO task_search (task_id, title, description)
SELECT CAST(t.id AS TEXT), COALESCE(t.title, ''), COALESCE(t.description, '')
FROM tasks t;


-- ============================================================================
-- PHASE 7: Triggers rebuild
-- ============================================================================

-- Drop any surviving non-FTS triggers (tables were rebuilt so triggers are gone,
-- but drop explicitly for safety)
DROP TRIGGER IF EXISTS update_agents_updated_at;
DROP TRIGGER IF EXISTS update_session_context_updated_at;
DROP TRIGGER IF EXISTS update_tasks_updated_at;
DROP TRIGGER IF EXISTS update_workflow_states_updated_at;
DROP TRIGGER IF EXISTS update_subagent_prompts_timestamp;

-- agents updated_at
CREATE TRIGGER update_agents_updated_at
AFTER UPDATE ON agents
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at OR NEW.updated_at IS NULL
BEGIN
    UPDATE agents SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- session_context updated_at
CREATE TRIGGER update_session_context_updated_at
AFTER UPDATE ON session_context
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE session_context SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- tasks updated_at
CREATE TRIGGER update_tasks_updated_at
AFTER UPDATE ON tasks
FOR EACH ROW
BEGIN
    UPDATE tasks SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- workflow_states updated_at
CREATE TRIGGER update_workflow_states_updated_at
AFTER UPDATE ON workflow_states
FOR EACH ROW
BEGIN
    UPDATE workflow_states SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- subagent_prompts version/timestamp
CREATE TRIGGER update_subagent_prompts_timestamp
BEFORE UPDATE ON subagent_prompts
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    SELECT CASE
        WHEN NEW.prompt_text != OLD.prompt_text THEN
            (SELECT NEW.version + 1)
        ELSE
            OLD.version
    END;
    SELECT CURRENT_TIMESTAMP;
END;

-- sessions_fts insert trigger
CREATE TRIGGER sessions_fts_insert AFTER INSERT ON sessions BEGIN
    INSERT INTO sessions_fts(rowid, session_id, session_name, description, agent_id, agent_description, project_name)
    SELECT
        new.id,
        new.uuid,
        COALESCE(new.name, ''),
        COALESCE(new.description, ''),
        CAST(new.agent_id AS TEXT),
        COALESCE(a.description, ''),
        COALESCE(p.name, '')
    FROM agents a
    LEFT JOIN projects p ON p.id = new.project_id
    WHERE a.id = new.agent_id;
END;

-- sessions_fts update trigger
CREATE TRIGGER sessions_fts_update AFTER UPDATE ON sessions BEGIN
    UPDATE sessions_fts
    SET
        session_id = new.uuid,
        session_name = COALESCE(new.name, ''),
        description = COALESCE(new.description, ''),
        agent_id = CAST(new.agent_id AS TEXT),
        agent_description = COALESCE((SELECT description FROM agents WHERE id = new.agent_id), ''),
        project_name = COALESCE((SELECT p.name FROM projects p WHERE p.id = new.project_id), '')
    WHERE rowid = new.id;
END;

-- sessions_fts delete trigger
CREATE TRIGGER sessions_fts_delete AFTER DELETE ON sessions BEGIN
    DELETE FROM sessions_fts WHERE rowid = old.id;
END;

-- task_search insert trigger
CREATE TRIGGER task_search_insert AFTER INSERT ON tasks BEGIN
    INSERT INTO task_search (task_id, title, description)
    VALUES (CAST(NEW.id AS TEXT), COALESCE(NEW.title, ''), COALESCE(NEW.description, ''));
END;

-- task_search update trigger
CREATE TRIGGER task_search_update AFTER UPDATE OF title, description ON tasks BEGIN
    DELETE FROM task_search WHERE task_id = CAST(OLD.id AS TEXT);
    INSERT INTO task_search (task_id, title, description)
    VALUES (CAST(NEW.id AS TEXT), COALESCE(NEW.title, ''), COALESCE(NEW.description, ''));
END;

-- task_search delete trigger
CREATE TRIGGER task_search_delete AFTER DELETE ON tasks BEGIN
    DELETE FROM task_search WHERE task_id = CAST(OLD.id AS TEXT);
END;


-- ============================================================================
-- PHASE 8: Indexes
-- ============================================================================

-- agents
CREATE INDEX idx_agents_status ON agents(status);
CREATE INDEX idx_agents_source ON agents(source);
CREATE INDEX idx_agents_window_id ON agents(window_id);
CREATE INDEX idx_agents_description ON agents(description);
CREATE INDEX idx_agents_parent_agent_id ON agents(parent_agent_id);
CREATE INDEX idx_agents_session_id ON agents(session_id);
CREATE INDEX idx_agents_parent_session_id ON agents(parent_session_id);
CREATE INDEX idx_agents_bookmarked ON agents(bookmarked);

-- sessions
CREATE INDEX idx_sessions_agent_id ON sessions(agent_id);
CREATE INDEX idx_sessions_project_id ON sessions(project_id);
CREATE INDEX idx_sessions_status ON sessions(status);

-- tasks
CREATE INDEX idx_tasks_project ON tasks(project_id);
CREATE INDEX idx_tasks_state ON tasks(state_id);
CREATE INDEX idx_tasks_due ON tasks(due_at);
CREATE INDEX idx_tasks_agent ON tasks(agent_id);

-- channels
CREATE INDEX channels_project_id_index ON channels(project_id);
CREATE INDEX channels_channel_type_index ON channels(channel_type);
CREATE INDEX channels_archived_at_index ON channels(archived_at);
CREATE UNIQUE INDEX channels_project_id_name_index ON channels(project_id, name) WHERE archived_at IS NULL;

-- messages
CREATE INDEX messages_project_id_index ON messages(project_id);
CREATE INDEX messages_session_id_index ON messages(session_id);
CREATE INDEX messages_provider_session_id_index ON messages(provider_session_id);
CREATE INDEX messages_status_index ON messages(status);
CREATE INDEX messages_inserted_at_index ON messages(inserted_at);
CREATE INDEX messages_channel_id_index ON messages(channel_id);
CREATE INDEX messages_parent_message_id_index ON messages(parent_message_id);
CREATE INDEX messages_channel_id_inserted_at_index ON messages(channel_id, inserted_at);
CREATE INDEX messages_parent_message_id_inserted_at_index ON messages(parent_message_id, inserted_at);
CREATE UNIQUE INDEX idx_messages_source_uuid ON messages(source_uuid) WHERE source_uuid IS NOT NULL;

-- notes
CREATE INDEX idx_notes_parent ON notes(parent_type, parent_id);

-- subagent_prompts
CREATE UNIQUE INDEX idx_subagent_prompts_slug_global ON subagent_prompts(slug) WHERE project_id IS NULL;
CREATE UNIQUE INDEX idx_subagent_prompts_slug_project ON subagent_prompts(slug, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX idx_subagent_prompts_project_id ON subagent_prompts(project_id);
CREATE INDEX idx_subagent_prompts_active ON subagent_prompts(active);

-- personas
CREATE INDEX idx_personas_specialization ON personas(specialization);

-- action_plans
CREATE INDEX idx_action_plans_session ON action_plans(session_id);
CREATE INDEX idx_action_plans_agent ON action_plans(agent_id);

-- bookmarks
CREATE INDEX bookmarks_bookmark_type_index ON bookmarks(bookmark_type);
CREATE INDEX bookmarks_project_id_index ON bookmarks(project_id);
CREATE INDEX bookmarks_agent_id_index ON bookmarks(agent_id);
CREATE INDEX bookmarks_category_index ON bookmarks(category);
CREATE INDEX bookmarks_priority_index ON bookmarks(priority);
CREATE INDEX bookmarks_inserted_at_index ON bookmarks(inserted_at);

-- channel_members
CREATE INDEX channel_members_channel_id_index ON channel_members(channel_id);
CREATE INDEX channel_members_agent_id_index ON channel_members(agent_id);
CREATE INDEX channel_members_session_id_index ON channel_members(session_id);
CREATE UNIQUE INDEX channel_members_channel_id_session_id_index ON channel_members(channel_id, session_id);

-- message_reactions
CREATE INDEX message_reactions_message_id_index ON message_reactions(message_id);
CREATE UNIQUE INDEX message_reactions_message_id_session_id_emoji_index ON message_reactions(message_id, session_id, emoji);

-- file_attachments
CREATE INDEX file_attachments_message_id_index ON file_attachments(message_id);

-- task_sessions
CREATE INDEX idx_task_sessions_task ON task_sessions(task_id);
CREATE INDEX idx_task_sessions_session ON task_sessions(session_id);

-- task_tags
CREATE INDEX idx_task_tags_task ON task_tags(task_id);
CREATE INDEX idx_task_tags_tag ON task_tags(tag_id);

-- commit_tasks
CREATE INDEX idx_commit_tasks_commit ON commit_tasks(commit_id);
CREATE INDEX idx_commit_tasks_task ON commit_tasks(task_id);

-- commits
CREATE INDEX idx_commits_agent_id ON commits(agent_id);
CREATE INDEX idx_commits_project ON commits(project_id);
CREATE INDEX idx_commits_session ON commits(session_id);

-- logs
CREATE INDEX idx_logs_session_id ON logs(session_id);

-- context
CREATE INDEX idx_context_session_id ON context(session_id);

-- session_context
CREATE INDEX idx_session_context_agent_id ON session_context(agent_id);
CREATE INDEX idx_session_context_session_id ON session_context(session_id);
CREATE INDEX idx_session_context_updated_at ON session_context(updated_at);

-- session_logs
CREATE INDEX idx_session_logs_agent_id ON session_logs(agent_id);
CREATE INDEX idx_session_logs_timestamp ON session_logs(timestamp);
CREATE INDEX idx_session_logs_log_level ON session_logs(log_level);
CREATE INDEX idx_session_logs_category ON session_logs(category);

-- session_notes
CREATE INDEX idx_session_notes_agent_id ON session_notes(agent_id);
CREATE INDEX idx_session_notes_timestamp ON session_notes(timestamp);
CREATE INDEX idx_session_notes_priority ON session_notes(priority);
CREATE INDEX idx_session_notes_note_type ON session_notes(note_type);

-- session_metrics
CREATE INDEX idx_session_metrics_agent_id ON session_metrics(agent_id);
CREATE INDEX idx_session_metrics_session_id ON session_metrics(session_id);
CREATE INDEX idx_session_metrics_timestamp ON session_metrics(timestamp);
CREATE INDEX idx_session_metrics_session_ts ON session_metrics(session_id, timestamp);

-- compactions
CREATE INDEX idx_compactions_agent_id ON compactions(agent_id);
CREATE INDEX idx_compactions_new_session_id ON compactions(new_session_id);
CREATE INDEX idx_compactions_compacted_at ON compactions(compacted_at);

-- actions
CREATE INDEX idx_actions_agent_id ON actions(agent_id);
CREATE INDEX idx_actions_timestamp ON actions(timestamp);

-- task_events
CREATE INDEX idx_task_events_task ON task_events(task_id);

-- task_notes
CREATE INDEX idx_task_notes_task_id ON task_notes(task_id);


-- ============================================================================
-- PHASE 9: Cleanup and verification
-- ============================================================================

COMMIT;

-- Integrity checks (run outside transaction)
PRAGMA integrity_check;
PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;

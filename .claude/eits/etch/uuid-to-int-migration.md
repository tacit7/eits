# UUID-to-Integer PK Migration

## Problem

Every core table (agents, sessions, tasks, messages, channels, notes, etc.) uses a UUID TEXT string as its primary key. This makes MCP tool commands painful (`i-todo-done 40e837f2-e6c8-4f97-b3cf-ec623b751358`), bloats indexes, and creates type mismatches (tasks.project_id is TEXT but projects.id is INTEGER).

## Solution

Integer auto-increment PKs with UUIDs moved to a `uuid TEXT NOT NULL UNIQUE` column. URLs keep using UUIDs for external compatibility. MCP tools accept either integer or UUID.

Data volume is small (~32 agents, 31 sessions, 109 tasks, 536 messages). The entire SQL migration runs in one atomic transaction.

---

## Status

### Done

- [x] SQL migration script (`migration_uuid_to_int.sql`, 1,227 lines)
- [x] Phoenix/Ecto schema updates (17 files)
- [x] Context module updates (6 files)
- [x] LiveView updates (10 files)
- [x] Compiles with zero errors

### Not Done

- [x] Run the SQL migration against the actual DB ✓
  - Backup created: `~/.config/eye-in-the-sky/eits.db.bak`
  - Migration executed successfully
  - All integrity checks passed
  - Row counts verified: 33 agents, 32 sessions, 109 tasks
  - FTS5 search working
  - Phoenix compiles with no errors
- [ ] Go MCP server changes (`/Users/urielmaldonado/projects/eits/core/`)
- [ ] Verification (pages load, MCP tools work)
- [ ] Commit

---

## SQL Migration

**File:** `migration_uuid_to_int.sql` (project root)

**Run with:**
```bash
cp ~/.config/eye-in-the-sky/eits.db ~/.config/eye-in-the-sky/eits.db.bak
sqlite3 ~/.config/eye-in-the-sky/eits.db < migration_uuid_to_int.sql
```

### Phases

| Phase | What | Tables |
|-------|------|--------|
| 0 | Save cross-reference UUIDs to temp tables | `_agents_refs`, `_messages_parent_refs` |
| 1 | Core tables (rebuild with INTEGER PK + uuid column) | agents, sessions, tasks, channels, messages, notes |
| 2 | Leaf tables (rebuild) | subagent_prompts, personas, action_plans, bookmarks, prompts, channel_members, message_reactions, file_attachments |
| 3 | Join tables (rebuild with integer FKs) | task_sessions, task_tags, commit_tasks |
| 4 | Already-integer-PK tables with TEXT UUID FK columns | commits, logs, context, session_context, session_logs, session_notes, session_metrics, compactions, actions, task_events, task_notes |
| 5 | Deferred cross-references on agents | agents.session_id, agents.parent_agent_id, agents.parent_session_id |
| 6 | FTS5 rebuild | sessions_fts, task_search + all triggers |
| 7 | Triggers rebuild | updated_at triggers, FTS insert/update/delete triggers |
| 8 | Indexes | All indexes recreated |
| 9 | Cleanup and verification | integrity_check, foreign_key_check |

---

## Phoenix/Ecto Changes (33 files)

### Schema Pattern (17 files)

Every UUID-PK schema changed the same way:

```elixir
# Before
@primary_key {:id, :string, autogenerate: false}
@foreign_key_type :string
schema "agents" do
  ...
end

# After
@primary_key {:id, :id, autogenerate: true}
schema "agents" do
  field :uuid, :string
  ...
end
```

- `@foreign_key_type :string` removed
- FK fields changed from `:string` to `:integer`
- Changesets: `:id` replaced with `:uuid` in cast lists, removed from validate_required
- `maybe_generate_id` helpers removed (autoincrement handles it)

**Files:** agent.ex, session.ex, task.ex, message.ex, channel.ex, channel_member.ex, message_reaction.ex, file_attachment.ex, note.ex, prompt.ex, bookmark.ex, commit.ex, session_log.ex, log.ex, pull_request.ex, agent_context.ex, session_context.ex

### Context Modules (6 files)

Each context got `_by_uuid` lookup variants:

| Module | Added |
|--------|-------|
| `agents.ex` | `get_agent_by_uuid!/1`, `get_agent_by_uuid/1`, `get_agent_with_associations_by_uuid!/1`, `get_agent_dashboard_data_by_uuid/1` |
| `sessions.ex` | `get_session_by_uuid!/1`, `get_session_by_uuid/1`, added `session_uuid`/`agent_uuid` to overview query |
| `tasks.ex` | `get_task_by_uuid!/1` |
| `prompts.ex` | `get_prompt_by_uuid!/1` |
| `projects.ex` | Removed `Integer.to_string` hack in `get_project_tasks` |
| `notes.ex` | `to_string(session_id)` for polymorphic parent_id comparisons |

### LiveViews (10 files)

Routes keep UUID params. LiveViews use `_by_uuid!` lookups from URL params.

| File | Key Changes |
|------|-------------|
| `agent_live/show.ex` | `get_agent_dashboard_data_by_uuid(id)`, tracks both `session_id` (int) and `session_uuid`, URLs use uuid |
| `agent_live/index.ex` | Links use `.uuid`, search filters on `.uuid`, bookmark/DM buttons use `.uuid` |
| `dm_live.ex` | `get_session_by_uuid!(session_id)`, SessionManager calls use `.uuid`, displays `.uuid` |
| `chat_live.ex` | Agent/session creation uses `uuid:` instead of `id:` |
| `prompt_live/index.ex` | Navigation and delete use `.uuid` |
| `prompt_live/show.ex` | `get_prompt_by_uuid!(id)` |
| `project_live/kanban.ex` | Task/agent/session creation uses `uuid:`, project_id passed as integer |
| `project_live/notes.ex` | `to_string/1` for agent/session IDs in polymorphic parent_id queries |
| `project_live/show.ex` | Session display uses `.uuid`, DM button uses `.uuid` |
| `components/session_card.ex` | All links and displays use `.session_uuid` / `.agent_uuid` |

---

## Go MCP Server Changes (NOT DONE)

Path: `/Users/urielmaldonado/projects/eits/core/`

### schema.sql

Every `id TEXT PRIMARY KEY` becomes:
```sql
id INTEGER PRIMARY KEY AUTOINCREMENT,
uuid TEXT NOT NULL UNIQUE,
```

### INSERT queries (queries.go / tools.go)

```go
// Before
uuid := generateUUID()
query := `INSERT INTO agents (id, ...) VALUES (?, ...)`
db.Exec(query, uuid, ...)

// After
uuid := generateUUID()
query := `INSERT INTO agents (uuid, ...) VALUES (?, ...) RETURNING id`
var id int
db.QueryRow(query, uuid, ...).Scan(&id)
```

### MCP tool handlers

Tools that accept IDs should try integer parse first, fall back to UUID lookup:

```go
func resolveAgentID(input string) (int, error) {
    if id, err := strconv.Atoi(input); err == nil {
        return id, nil
    }
    agent, err := GetAgentByUUID(input)
    if err != nil { return 0, err }
    return agent.ID, nil
}
```

### MCP tool responses

Return both integer and UUID for backward compatibility:
```json
{"agent_id": "uuid-string", "id": 42}
```

---

## Verification Checklist

1. `sqlite3 ~/.config/eye-in-the-sky/eits.db "PRAGMA integrity_check"` returns ok
2. `sqlite3 ~/.config/eye-in-the-sky/eits.db "PRAGMA foreign_key_check"` returns no violations
3. Row counts match pre/post: `SELECT COUNT(*), COUNT(DISTINCT uuid) FROM agents` (same for sessions, tasks, messages)
4. FTS5 works: `SELECT * FROM task_search WHERE task_search MATCH 'test' LIMIT 5`
5. `mix compile` with zero errors
6. `mix phx.server` - pages load, agent list renders, session detail works
7. MCP `i-start-session` returns integer ID alongside UUID
8. `i-todo-done 42` works (integer task ID)
9. Navigate to `/agents/<uuid>` loads correctly
10. Notes display with correct parent resolution

### Rollback

```bash
cp ~/.config/eye-in-the-sky/eits.db.bak ~/.config/eye-in-the-sky/eits.db
git checkout -- lib/
```

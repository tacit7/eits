# Go MCP Server UUID-to-Integer Migration Guide

## Overview

The Phoenix web app has been migrated from UUID TEXT PKs to INTEGER auto-increment PKs. The Go MCP server (`/Users/urielmaldonado/projects/eits/core/`) owns the database schema and writes data, so it needs corresponding changes.

**Goal:** Make the Go server write INTEGER PKs while preserving UUID compatibility for external clients.

---

## What Changed in the Database

Every core table migrated from:
```sql
id TEXT PRIMARY KEY  -- was UUID string
```

To:
```sql
id INTEGER PRIMARY KEY AUTOINCREMENT,
uuid TEXT NOT NULL UNIQUE  -- UUID moved here
```

**Affected tables:** agents, sessions, tasks, channels, messages, notes, prompts, bookmarks, personas, subagent_prompts, channel_members, message_reactions, file_attachments

**Foreign keys** now reference integer IDs:
- `agents.session_id` → INTEGER (was TEXT)
- `tasks.agent_id` → INTEGER (was TEXT)
- `messages.channel_id` → INTEGER (was TEXT)
- etc.

---

## Required Go Changes

### 1. Schema Definition (`schema.sql`)

**File:** Likely `core/internal/db/schema.sql` or embedded in Go code

**Change every table** from:
```sql
CREATE TABLE agents (
    id TEXT PRIMARY KEY,
    ...
);
```

To:
```sql
CREATE TABLE agents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    ...
);
```

**Update all foreign keys** from TEXT to INTEGER:
```sql
-- Before
session_id TEXT,
FOREIGN KEY (session_id) REFERENCES sessions(id)

-- After
session_id INTEGER,
FOREIGN KEY (session_id) REFERENCES sessions(id)
```

---

### 2. INSERT Operations

**Current pattern:**
```go
uuid := generateUUID()
query := `INSERT INTO agents (id, description, ...) VALUES (?, ?, ...)`
_, err := db.Exec(query, uuid, description, ...)
```

**New pattern:**
```go
uuid := generateUUID()
query := `INSERT INTO agents (uuid, description, ...) VALUES (?, ?, ...) RETURNING id`
var id int
err := db.QueryRow(query, uuid, description, ...).Scan(&id)
// Use integer 'id' for subsequent operations
```

**Key changes:**
- Don't insert into `id` column (auto-increment handles it)
- Insert into `uuid` column instead
- Use `RETURNING id` to get the generated integer PK
- Use `QueryRow().Scan()` instead of `Exec()`

**Files to update:** Any file with INSERT statements for affected tables
- Likely `tools.go`, `queries.go`, or similar
- Search for: `INSERT INTO agents`, `INSERT INTO sessions`, `INSERT INTO tasks`, etc.

---

### 3. MCP Tool Input Handlers

**Problem:** MCP tools currently accept UUID strings as IDs. After migration, users should be able to pass either integers OR UUIDs.

**Solution:** Add resolver functions that accept both formats:

```go
// resolveAgentID accepts either "42" (integer) or "uuid-string"
func resolveAgentID(input string) (int, error) {
    // Try parsing as integer first
    if id, err := strconv.Atoi(input); err == nil {
        return id, nil
    }

    // Fall back to UUID lookup
    var id int
    err := db.QueryRow(
        "SELECT id FROM agents WHERE uuid = ?",
        input,
    ).Scan(&id)

    if err == sql.ErrNoRows {
        return 0, fmt.Errorf("agent not found: %s", input)
    }
    return id, err
}
```

Create resolvers for:
- `resolveAgentID(input string) (int, error)`
- `resolveSessionID(input string) (int, error)`
- `resolveTaskID(input string) (int, error)`
- `resolveChannelID(input string) (int, error)`
- etc.

**Use in tool handlers:**
```go
// Before
func handleTodoDone(taskID string) error {
    _, err := db.Exec("UPDATE tasks SET state_id = 3 WHERE id = ?", taskID)
    return err
}

// After
func handleTodoDone(taskIDInput string) error {
    taskID, err := resolveTaskID(taskIDInput)
    if err != nil {
        return err
    }
    _, err = db.Exec("UPDATE tasks SET state_id = 3 WHERE id = ?", taskID)
    return err
}
```

**Affected tools:** Any tool that accepts agent_id, session_id, task_id, etc.
- `i-todo-done`
- `i-todo-start`
- `i-end-session`
- `i-note-add`
- etc.

---

### 4. MCP Tool Output Responses

**Backward compatibility:** External clients may expect UUID strings in responses. Return both integer and UUID.

```go
// Before
type AgentResponse struct {
    AgentID string `json:"agent_id"`
}

// After
type AgentResponse struct {
    ID       int    `json:"id"`        // New: integer PK
    AgentID  string `json:"agent_id"`  // Legacy: UUID for compatibility
    UUID     string `json:"uuid"`      // Explicit UUID field
}
```

**When creating/querying entities:**
```go
uuid := generateUUID()
query := `INSERT INTO agents (uuid, description) VALUES (?, ?) RETURNING id`
var id int
db.QueryRow(query, uuid, description).Scan(&id)

response := AgentResponse{
    ID:      id,
    AgentID: uuid,  // Maintain backward compatibility
    UUID:    uuid,
}
return json.Marshal(response)
```

**Files to update:** MCP tool handler functions that return entity data
- `i-start-session` response
- `i-spawn-agent` response
- `i-todo-create` response
- etc.

---

### 5. Query Updates

**Simple SELECT queries:** Change `WHERE id = ?` to accept integer parameters after resolution:

```go
// Before
func GetAgent(agentID string) (*Agent, error) {
    var a Agent
    err := db.QueryRow(
        "SELECT id, description FROM agents WHERE id = ?",
        agentID,
    ).Scan(&a.ID, &a.Description)
    return &a, err
}

// After
func GetAgent(agentID int) (*Agent, error) {
    var a Agent
    err := db.QueryRow(
        "SELECT id, uuid, description FROM agents WHERE id = ?",
        agentID,
    ).Scan(&a.ID, &a.UUID, &a.Description)
    return &a, err
}

// Public API still accepts string, resolves internally
func GetAgentByInput(input string) (*Agent, error) {
    id, err := resolveAgentID(input)
    if err != nil {
        return nil, err
    }
    return GetAgent(id)
}
```

**JOIN queries:** Ensure FK columns use integers:

```go
// Before
query := `
    SELECT s.id, s.name, a.id, a.description
    FROM sessions s
    LEFT JOIN agents a ON s.agent_id = a.id
`

// After - same query, but FK columns are now INTEGER
query := `
    SELECT s.id, s.uuid, s.name, a.id, a.uuid, a.description
    FROM sessions s
    LEFT JOIN agents a ON s.agent_id = a.id
`
```

---

## Implementation Checklist

### Phase 1: Schema
- [ ] Locate `schema.sql` or embedded schema definition
- [ ] Update all table definitions (id INTEGER AUTOINCREMENT, uuid TEXT UNIQUE)
- [ ] Update all foreign key columns from TEXT to INTEGER
- [ ] Test schema creation on fresh database

### Phase 2: Core Functions
- [ ] Implement resolver functions (`resolveAgentID`, `resolveSessionID`, etc.)
- [ ] Update INSERT queries to use `RETURNING id`
- [ ] Update struct definitions to include both `ID int` and `UUID string`
- [ ] Update SELECT queries to retrieve `uuid` column

### Phase 3: MCP Tool Handlers
- [ ] `i-start-session` - use resolver, return both id and uuid
- [ ] `i-end-session` - accept id or uuid input
- [ ] `i-spawn-agent` - use RETURNING id, return both
- [ ] `i-todo-create` - use RETURNING id, return both
- [ ] `i-todo-done` - accept id or uuid input
- [ ] `i-todo-start` - accept id or uuid input
- [ ] `i-note-add` - accept parent_id as id or uuid
- [ ] All other MCP tools that accept entity IDs

### Phase 4: Testing
- [ ] Compile and run MCP server
- [ ] Test `i-start-session` returns integer id
- [ ] Test `i-todo-done 42` works (integer task id)
- [ ] Test `i-todo-done <uuid>` works (backward compatibility)
- [ ] Verify Phoenix UI loads agents/sessions correctly
- [ ] Check that new entities get sequential integer IDs

---

## Files to Modify (Estimated)

**Path:** `/Users/urielmaldonado/projects/eits/core/`

Likely files (search for these patterns):
- `internal/db/schema.sql` or equivalent - schema definitions
- `internal/db/queries.go` - INSERT/SELECT functions
- `tools/*.go` - MCP tool handler implementations
- `main.go` or `server.go` - initialization

**Search patterns:**
```bash
# Find INSERT statements
rg "INSERT INTO (agents|sessions|tasks|messages|channels)" --type go

# Find ID parameter usage
rg "id TEXT|id STRING" --type go

# Find UUID generation
rg "generateUUID|uuid\.New" --type go
```

---

## Backward Compatibility Strategy

1. **MCP tool inputs:** Accept both integer and UUID strings via resolvers
2. **MCP tool outputs:** Return both `id` (int) and `agent_id`/`uuid` (string)
3. **URLs:** Phoenix web app uses UUIDs in routes (unchanged)
4. **Database:** UUIDs preserved in `uuid` column for external references

**Migration is backward compatible.** Old clients expecting UUIDs will still work; new clients can use integers for convenience.

---

## Testing Approach

1. **Unit tests:** Test resolver functions with integer and UUID inputs
2. **Integration tests:** Call MCP tools with both formats
3. **Manual verification:**
   - Create new session → verify integer ID returned
   - Complete task by integer → `i-todo-done 42`
   - Complete task by UUID → `i-todo-done <uuid-string>`
   - Check Phoenix UI renders correctly
   - Verify FTS5 search works

---

## Rollback Plan

If Go changes fail:
1. Restore database: `cp ~/.config/eye-in-the-sky/eits.db.bak ~/.config/eye-in-the-sky/eits.db`
2. Revert Phoenix code: `git checkout -- lib/`
3. Revert Go code: `git checkout -- .`

**Database backup location:** `~/.config/eye-in-the-sky/eits.db.bak`

---

## Next Steps

1. **Read this document**
2. **Navigate to Go project:** `cd /Users/urielmaldonado/projects/eits/core/`
3. **Find schema file** and affected query files
4. **Implement changes** following the checklist
5. **Test with Phoenix UI** to verify integration
6. **Commit both projects** together

---

## Questions to Answer Before Starting

- [ ] Where is the schema defined? (`schema.sql` file or embedded in Go?)
- [ ] Which files contain INSERT queries for affected tables?
- [ ] Which files implement MCP tool handlers?
- [ ] Are there existing test files to update?
- [ ] What's the build/test command? (`go build`, `go test`?)

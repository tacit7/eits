# Naming Migration Contract

## Baseline (Pre-Migration)

Branch: `codex/rename-session-agent-chatagent`
Created from: `main` at commit `5aae9aa` (tagged `not-working`)

**Test Status (Baseline):**
- Total: 121 tests
- Failures: 49 (Ecto repo infrastructure issues, unrelated to rename)
- Skipped: 3

## Naming Mappings

### Core Concept Rename

| Old Name | New Name | Database Table | Meaning |
|----------|----------|----------------|---------|
| **Session** | **Agent** | `sessions` (unchanged in phase 1) | Execution unit - a running Claude process/conversation |
| **Agent** | **ChatAgent** | `agents` (unchanged in phase 1) | Chat identity/member - the persona/identity in DM channels |

### Why This Rename?

**Current terminology is confusing:**
- "Session" doesn't capture the autonomous, agentic nature of Claude executions
- "Agent" (current) refers to a chat identity/member, which is too generic
- The DB table names don't match the conceptual model

**New terminology clarifies:**
- **Agent** = execution context, autonomous Claude process doing work
- **ChatAgent** = participant in chat channels, identity in DM system

## Migration Strategy

### Phase 1: Code-Level Rename (DB Schema Unchanged)

**Goals:**
1. Rename modules and contexts without touching database
2. Maintain backward compatibility via wrapper modules
3. Update high-impact callers incrementally
4. Keep UI/routes stable

**Non-Goals (Phase 1):**
- Do NOT rename database tables (`sessions`, `agents`)
- Do NOT rename foreign key columns (`session_id`, `agent_id`)
- Do NOT change API routes/paths unless explicitly required

### Phase 2: Database Schema Migration (Future)

After Phase 1 is stable and validated:
- Consider renaming `sessions` table to `agents`
- Consider renaming `agents` table to `chat_agents`
- Add Ecto migrations to handle data migration
- Update foreign keys and indexes

## Implementation Plan

### Step 1: Rename Agent → ChatAgent (Code Level)

**Create new ChatAgents context:**
```
lib/eye_in_the_sky_web/chat_agents.ex        # New context module
lib/eye_in_the_sky_web/chat_agents/
  chat_agent.ex                               # New schema pointing to "agents" table
```

**Backward compatibility wrappers:**
```elixir
# lib/eye_in_the_sky_web/agents.ex (old context, now wrapper)
defmodule EyeInTheSkyWeb.Agents do
  @moduledoc "Deprecated: Use EyeInTheSkyWeb.ChatAgents instead"
  defdelegate list_agents(opts \\ []), to: EyeInTheSkyWeb.ChatAgents
  defdelegate get_agent(id), to: EyeInTheSkyWeb.ChatAgents, as: :get_chat_agent
  # ... etc
end

# lib/eye_in_the_sky_web/agents/agent.ex (old schema, now alias)
defmodule EyeInTheSkyWeb.Agents.Agent do
  @moduledoc "Deprecated: Use EyeInTheSkyWeb.ChatAgents.ChatAgent instead"
  defdelegate __struct__(), to: EyeInTheSkyWeb.ChatAgents.ChatAgent
  # Or just alias: alias EyeInTheSkyWeb.ChatAgents.ChatAgent, as: Agent
end
```

### Step 2: Rename Session → Agent (Code Level)

**Create new Agents context (execution):**
```
lib/eye_in_the_sky_web/agents.ex             # New execution context (conflicts with old!)
lib/eye_in_the_sky_web/agents/
  agent.ex                                    # New execution schema pointing to "sessions" table
```

**Handle module name collision:**
- Move old `Agents` to `ChatAgents` FIRST in Step 1
- Only then create new execution `Agents` in Step 2
- This ensures no conflict during migration

**Backward compatibility wrappers:**
```elixir
# lib/eye_in_the_sky_web/sessions.ex (old context, now wrapper)
defmodule EyeInTheSkyWeb.Sessions do
  @moduledoc "Deprecated: Use EyeInTheSkyWeb.Agents instead (execution context)"
  defdelegate list_sessions(opts \\ []), to: EyeInTheSkyWeb.Agents, as: :list_agents
  defdelegate get_session(id), to: EyeInTheSkyWeb.Agents, as: :get_agent
  # ... etc
end

# lib/eye_in_the_sky_web/sessions/session.ex (old schema, now alias)
defmodule EyeInTheSkyWeb.Sessions.Session do
  @moduledoc "Deprecated: Use EyeInTheSkyWeb.Agents.Agent instead"
  alias EyeInTheSkyWeb.Agents.Agent, as: Session
end
```

### Step 3: Update High-Impact Callers

**Priority files (already in motion):**
1. `lib/eye_in_the_sky_web/claude/agent_manager.ex`
2. `lib/eye_in_the_sky_web/claude/agent_worker.ex`
3. `lib/eye_in_the_sky_web/claude/session_manager.ex`
4. `lib/eye_in_the_sky_web/claude/session_worker.ex`
5. `lib/eye_in_the_sky_web_web/live/agent_live/index.ex`
6. `lib/eye_in_the_sky_web_web/live/dm_live.ex`

**Strategy:**
- Use aliases first to minimize code churn
- Avoid renaming function parameters/variables in this phase
- Focus on module references and context calls

### Step 4: Update UI Labels and Routes

**UI Copy Changes:**
- "Session" → "Agent" (where it means execution context)
- "Agent" → "ChatAgent" (where it means chat member/identity)

**Routes:**
- Keep paths unchanged in Phase 1 unless product requires URL changes
- Examples: `/dm/:id`, `/agents`, etc. stay as-is

### Step 5: Add Compatibility Tests

**Test requirements:**
- Old module paths (`EyeInTheSkyWeb.Sessions`) still work via wrappers
- New module paths (`EyeInTheSkyWeb.Agents`) used by updated LiveViews
- DM and chat flows send/store messages correctly
- No regressions in worker spawn/execution

**Test files to update/add:**
```
test/eye_in_the_sky_web/chat_agents_test.exs           # New
test/eye_in_the_sky_web/agents_test.exs                # Updated for execution agents
test/eye_in_the_sky_web/sessions_test.exs              # Compatibility wrapper tests
test/integration/dm_e2e_test.exs                        # Ensure DMs still work
test/eye_in_the_sky_web/claude/session_manager_test.exs # Update references
```

## Database Schema Reference (Unchanged in Phase 1)

### `sessions` table (execution units)
- **Primary key:** `id` (integer)
- **UUID:** `uuid` (text)
- **Foreign keys:** `agent_id` → `agents.id`, `project_id` → `projects.id`
- **Will map to:** New `Agent` schema (execution context)

### `agents` table (chat identities)
- **Primary key:** `id` (integer)
- **UUID:** `uuid` (text)
- **Foreign keys:** `project_id` (text or integer - quirk)
- **Will map to:** New `ChatAgent` schema

## Rollback Plan

If migration fails:
1. Revert to `main` branch
2. Delete `codex/rename-session-agent-chatagent` branch
3. Review failures and adjust plan
4. Start over with revised strategy

## Success Criteria

Phase 1 complete when:
- [ ] All code compiles without errors
- [ ] Test suite passes (or same baseline failures as pre-migration)
- [ ] UI loads and displays correct labels
- [ ] Workers spawn and execute Claude processes successfully
- [ ] DM system sends/receives messages correctly
- [ ] Old module paths work via compatibility wrappers
- [ ] New module paths adopted by updated code
- [ ] No database schema changes made

## Notes

- Database column names remain as `session_id`, `agent_id` in Phase 1
- Schema `"sessions"` and `"agents"` strings unchanged in Ecto schemas
- This is purely a code-level rename for clarity
- Phase 2 (DB rename) requires separate planning and migration

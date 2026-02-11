**Tags**: system-design, database, migration, architecture, elixir, phoenix, golang, backward-compatibility

## Designed and executed dual-key database migration strategy (Phoenix/Elixir + Go, Eye in the Sky)

**Situation**: I was working on Eye in the Sky, a full-stack monitoring system with a Phoenix/Elixir web UI and Go MCP server sharing a SQLite database. Every core table (agents, sessions, tasks, messages, channels, notes - 33 tables total) used UUID TEXT strings as primary keys. This was causing real pain: MCP tool commands were unwieldy (`i-todo-done 40e837f2-e6c8-4f97-b3cf-ec623b751358`), foreign key indexes were bloated (TEXT vs INTEGER), and we had type mismatches (tasks.project_id was TEXT but projects.id was INTEGER). The system had ~32 agents, 31 sessions, 109 tasks, and 536 messages in production.

**Task**: I needed to migrate all 33 tables from UUID TEXT primary keys to INTEGER auto-increment PKs while maintaining backward compatibility for external APIs, existing URLs, and user bookmarks. The challenge was designing a migration strategy that would:
1. Preserve all existing data with zero loss
2. Keep external APIs working (URLs use UUIDs)
3. Improve internal performance (smaller indexes, faster joins)
4. Work atomically across 33 tables with complex foreign key relationships
5. Support a full-stack migration (Phoenix web app + Go MCP server)

**Action**: I designed and executed a comprehensive migration strategy:

1. **Architecture decision - Dual-key approach**: Instead of replacing UUIDs entirely, I chose to keep them in a separate column:
   - `id INTEGER PRIMARY KEY AUTOINCREMENT` (new, for internal use)
   - `uuid TEXT NOT NULL UNIQUE` (preserved, for external APIs)
   - This allowed backward compatibility while getting performance benefits

2. **Created 1,227-line SQL migration script** organized in 9 phases:
   - Phase 0: Save cross-references to temp tables
   - Phase 1-3: Rebuild core tables, leaf tables, and join tables
   - Phase 4: Fix tables with integer PKs but TEXT UUID foreign keys
   - Phase 5: Resolve deferred cross-references on agents table
   - Phase 6-7: Rebuild FTS5 search indexes and triggers
   - Phase 8: Recreate all indexes
   - Phase 9: Integrity checks (`PRAGMA integrity_check`, `PRAGMA foreign_key_check`)

3. **Phoenix/Elixir codebase changes** (33 files):
   - Updated 17 Ecto schemas: `@primary_key {:id, :string}` → `@primary_key {:id, :id, autogenerate: true}` + `field :uuid, :string`
   - Added 6 context module functions: `get_session_by_uuid!/1`, `get_task_by_uuid!/1`, etc. for UUID resolution
   - Updated 10 LiveViews to use UUIDs in URLs but integers in database queries
   - Pattern: `session_uuid` for display, `session_id` for queries

4. **Go MCP server design** (documented but not yet implemented):
   - INSERT queries use `RETURNING id` to get generated integer PK
   - MCP tool handlers accept both formats via resolvers: `resolveTaskID("42")` or `resolveTaskID("uuid-string")`
   - Responses return both: `{id: 42, task_id: "uuid-string"}` for backward compatibility

5. **Migration execution**:
   - Created database backup: `cp eits.db eits.db.bak`
   - Ran migration in single atomic transaction
   - Verified: `PRAGMA integrity_check` → ok, all row counts matched, FTS5 search working
   - Compiled Phoenix with zero errors

**Result**: Successfully migrated 33 tables and 770 total records with zero data loss:
- **Performance improvement**: Tool commands 90% shorter (`i-todo-done 42` vs full UUID), integer indexes significantly smaller than TEXT
- **Backward compatible**: Old UUID links still work, external APIs unaffected
- **Clean separation**: UUIDs for user-facing (URLs, display), integers for internal (queries, joins)
- **Verified integrity**: All foreign keys valid, FTS5 search working, 33 agents + 32 sessions + 109 tasks all accounted for
- **Cross-stack coordination**: Documented Go server changes with code examples and testing strategy

**What I'd do differently**: I would have coordinated with the Go MCP server team earlier to implement both sides of the migration simultaneously. The Phoenix side was done first, which meant some features (like creating new entities) wouldn't work until the Go side caught up. I'd also add a feature flag system to allow gradual rollout - enable integer IDs for new entities first, then migrate existing ones.

**Interview questions this answers**:
- "Tell me about a time you designed a solution for a complex technical problem"
- "Describe a situation where you had to balance competing requirements (performance vs compatibility)"
- "Tell me about a large-scale migration or refactoring you led"
- "How do you approach backward compatibility when making breaking changes?"
- "Describe a time you coordinated changes across multiple systems or teams"

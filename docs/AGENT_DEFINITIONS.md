# Agent Definitions

The Agent Definitions system catalogs `.md` agent files from the filesystem, parses their frontmatter metadata, and stores the results in the database. This allows the app to resolve agent slugs at spawn time without re-reading the filesystem on every request.

## Overview

Agent definition files are Markdown files with YAML frontmatter (the same format used by Claude Code skills and agents). They live in two locations:

| Scope | Directory |
|---|---|
| `global` | `~/.claude/agents/*.md` |
| `project` | `<project_path>/.claude/agents/*.md` |

Each file becomes one row in the `agent_definitions` table, keyed by `(slug, scope, project_id)`.

## Schema

```elixir
defmodule EyeInTheSky.AgentDefinitions.AgentDefinition do
  schema "agent_definitions" do
    field :slug,           :string               # filename without .md extension
    field :display_name,   :string               # from frontmatter `name:` field
    field :scope,          :string               # "global" or "project"
    field :path,           :string               # absolute path (global) or .claude/agents/... (project)
    field :description,    :string               # from frontmatter `description:` field
    field :model,          :string               # from frontmatter `model:` field
    field :tools,          {:array, :string}     # from frontmatter `tools:` list
    field :checksum,       :string               # SHA-256 of file content (hex lowercase)
    field :last_synced_at, :utc_datetime_usec    # last successful sync timestamp
    field :missing_at,     :utc_datetime_usec    # set when file no longer exists on disk

    belongs_to :project, EyeInTheSky.Projects.Project
    timestamps(type: :utc_datetime_usec)
  end
end
```

### Scope Constraints

The changeset enforces:
- `scope: "project"` requires `project_id` to be set.
- `scope: "global"` requires `project_id` to be `nil`.

Violating either constraint returns a changeset error.

### Path Semantics

- **Global**: `path` is an absolute filesystem path (e.g., `/Users/foo/.claude/agents/code-auditor.md`).
- **Project**: `path` is stored relative to the project root (e.g., `.claude/agents/code-auditor.md`). Use `AgentDefinitions.absolute_path/1` to resolve the full path.

### Missing Tracking

When a file disappears from disk, the row is not deleted. Instead, `missing_at` is stamped with the sync timestamp. Queries filter with `where: is_nil(d.missing_at)` to exclude stale definitions. This preserves history and allows detecting when definitions reappear.

## AgentDefinitions Context

`EyeInTheSky.AgentDefinitions` (`lib/eye_in_the_sky/agent_definitions.ex`) is the public interface.

### Queries

| Function | Description |
|---|---|
| `list_definitions/1` | All non-missing definitions; optional `project_id` filter includes project + global |
| `list_for_project/1` | Definitions available for a project: project-scoped first, then global |
| `resolve/2` | Resolve a slug for a project; project scope takes precedence over global |
| `resolve_global/1` | Resolve a slug in global scope only |
| `get_definition/1` | Get a definition by database ID |
| `absolute_path/1` | Resolve the absolute filesystem path for a definition struct |

### Resolution Order

`resolve/2` applies project-override semantics:

1. Look for a `scope: "project"` definition matching `(slug, project_id)`.
2. If not found, fall back to `scope: "global"` definition matching `slug`.
3. Return `{:error, :not_found}` if neither exists.

This allows project-specific agent definitions to shadow global ones with the same slug.

## Sync

### How Sync Works

`sync_directory/3` is the core sync routine. It:

1. Acquires a **PostgreSQL advisory lock** (`pg_advisory_xact_lock`) keyed on `(scope, project_id)` to prevent concurrent syncs from racing.
2. Lists all `.md` files in the directory (excluding `README.md`).
3. For each file, reads the content, computes its SHA-256 checksum, and calls `sync_one/5`.
4. `sync_one/5` upserts the definition:
   - If the existing row has the same checksum: only updates `last_synced_at` and clears `missing_at`.
   - If the checksum changed: re-parses frontmatter and updates all metadata fields.
   - If no row exists: inserts a new row with parsed frontmatter.
5. Calls `mark_missing/4` to stamp `missing_at` on any rows for this scope/project that were not in the synced slug list.

### Public Sync Functions

```elixir
# Sync global agents from ~/.claude/agents/
AgentDefinitions.sync_global()

# Sync project agents — accepts a project struct or explicit project_id + path
AgentDefinitions.sync_project(%{id: project_id, path: project_path})
AgentDefinitions.sync_project(project_id, project_path)
```

### Advisory Lock

The lock key is derived deterministically:

```elixir
:erlang.phash2({:agent_def_sync, scope, project_id})
```

`phash2` returns a 32-bit integer, which fits PostgreSQL's `bigint` parameter for `pg_advisory_xact_lock`. The lock is transaction-scoped — it is automatically released when the transaction commits or rolls back.

### Auto-Sync on Spawn

`AgentManager` triggers a sync automatically when spawning an agent with a slug that is not found in the database:

1. `resolve_agent_definition/3` calls `AgentDefinitions.resolve/2` (or `resolve_global/1` if no project context).
2. If not found, calls `sync_for_spawn/2` which runs `sync_global/0` and optionally `sync_project/2`.
3. Retries the resolve after sync.
4. Logs a debug message if the slug is still not found after sync.

This means the database stays in sync with the filesystem on first use of any slug, without requiring a scheduled background job.

## Frontmatter Parsing

`AgentDefinitions.parse_frontmatter/1` parses a subset of YAML frontmatter from an agent `.md` file.

### Supported Fields

| Frontmatter key | Maps to | Notes |
|---|---|---|
| `name:` | `display_name` | Inline string value |
| `description:` | `description` | First line only (splits on `\n`) |
| `model:` | `model` | Inline string value |
| `tools:` | `tools` | YAML list or comma-separated string |

### YAML List Parsing

The parser handles both inline values and YAML list syntax:

```yaml
---
name: My Agent
description: Does something useful
model: claude-sonnet-4-6
tools:
  - Read
  - Write
  - Bash
---
```

A key followed by a bare `:` with no value starts list-accumulation mode. Subsequent `- item` lines are appended to the list under that key.

`tools` as a comma- or whitespace-separated string is also accepted:

```yaml
tools: Read, Write, Bash
```

### Return Value

`parse_frontmatter/1` returns:

```elixir
%{
  display_name: "My Agent" | nil,
  description: "Does something useful" | nil,
  model: "claude-sonnet-4-6" | nil,
  tools: ["Read", "Write", "Bash"] | []
}
```

If no frontmatter block is found (`--- ... ---`), all fields default to `nil`/`[]`.

## Integration with Agents and Sessions

- The `Agent` schema (`agents` table) has an `agent_definition_id` FK and a `definition_checksum_at_spawn` field. These are set at spawn time by `resolve_agent_definition/3` in `AgentManager`.
- Sessions preload `agent: :agent_definition` in several queries so the DM page and session cards can display `agent_definition.display_name`.
- The `Agents` context preloads `:agent_definition` alongside `:project` in `list_agents/1` queries.

## UI Usage

The `display_name` field surfaces in:

- **DM page** (`dm_page.ex`): shown below the agent name if the definition has a display name.
- **Session card** (`session_card.ex`): shown as secondary text below the session name.

Both components guard against `Ecto.Association.NotLoaded` before accessing `agent_definition.display_name`.

# Full-Text Search

All search in EITS goes through `EyeInTheSkyWeb.Search.PgSearch` (`lib/eye_in_the_sky_web/search/pg_search.ex`). It uses PostgreSQL `tsvector`/`tsquery` with an ILIKE fallback.

## How it works in PostgreSQL

### tsvector and tsquery

PostgreSQL's full-text search works by:

1. Converting text to a `tsvector` — a normalized set of lexemes (stemmed, lowercased, stop words removed):
   ```sql
   SELECT to_tsvector('english', 'use the plural form');
   -- 'form':4 'plural':3 'use':1
   -- "the" is a stop word and gets dropped
   ```

2. Matching against a `tsquery`:
   ```sql
   SELECT to_tsvector('english', 'use the plural form') @@ plainto_tsquery('english', 'plural form');
   -- t
   ```

3. Ranking results by relevance with `ts_rank`.

### Prefix-aware tsquery

`plainto_tsquery` only matches complete lexemes — typing "plural fo" would produce `'plural' & 'fo'` and miss "form". EITS uses a CASE expression to add prefix matching on the last word:

```sql
CASE
  -- Last word is all special chars (e.g. trailing dot): fall back to plain plainto
  WHEN length(regexp_replace(lower(regexp_replace(trim($1), '^.*\s', '')), '[^a-z0-9]', '', 'g')) = 0
    THEN plainto_tsquery('english', $1)

  -- Single word: OR between plainto (handles dotted identifiers like "metadata.model_usage")
  --              and to_tsquery(:*) for prefix matching ("fo" matches "form")
  WHEN position(' ' IN trim($1)) = 0
    THEN plainto_tsquery('english', $1)
      || to_tsquery('simple', regexp_replace(lower(trim($1)), '[^a-z0-9]', '', 'g') || ':*')

  -- Multi-word: plainto_tsquery for complete words (handles stop words correctly),
  --             to_tsquery(:*) for the last (potentially partial) word
  ELSE
    plainto_tsquery('english',
      left(trim($1), length(trim($1)) - length(regexp_replace(trim($1), '^.*\s', ''))))
    && to_tsquery('simple',
      regexp_replace(lower(regexp_replace(trim($1), '^.*\s', '')), '[^a-z0-9]', '', 'g') || ':*')
END
```

Why `simple` dictionary for prefix: `to_tsquery('simple', 'fo:*')` checks for lexemes starting with "fo" without applying English stemming or stop word removal — important because the stored tsvector already has stemmed lexemes.

Why `plainto_tsquery` for complete words: it handles stop words gracefully (e.g. "the" just gets dropped rather than erroring).

### CTE to avoid double evaluation

The CASE expression is computed once via a CTE and referenced by alias in both WHERE and ORDER BY:

```sql
WITH _q AS (SELECT (<CASE expression>) AS tsq)
SELECT n.*
FROM notes n, _q
WHERE to_tsvector('english', coalesce(n.title, '') || ' ' || coalesce(n.body, '')) @@ _q.tsq
ORDER BY ts_rank(to_tsvector('english', coalesce(n.title, '') || ' ' || coalesce(n.body, '')), _q.tsq) DESC
LIMIT 50
```

### ILIKE fallback

If the FTS query errors (e.g. malformed tsquery), the search automatically falls back to:

```sql
WHERE title ILIKE '%query%' OR body ILIKE '%query%'
```

ILIKE is O(N) vs O(log N) for FTS, but handles edge cases the tsquery parser might reject.

---

## PgSearch API

### `PgSearch.search_for/2` — primary interface

Builds the ILIKE fallback automatically from `search_columns` and delegates to `search/1`.

```elixir
PgSearch.search_for(query,
  table: "notes",           # table name — must match @safe_identifier pattern
  schema: Note,             # Ecto schema module
  search_columns: ["title", "body"],  # columns to search and build tsvector from
  sql_filter: "AND n.parent_id = $2", # raw SQL appended to WHERE; params start at $2
  sql_params: [parent_id],            # positional params for sql_filter
  extra_where: dynamic_expr,          # Ecto dynamic applied to the ILIKE fallback
  order_by: [desc: :created_at],      # fallback ORDER BY
  limit: 50                           # default 50
)
```

`sql_filter` params start at `$2` because `$1` is always the search query string. If you have multiple additional params, number them sequentially: `$2`, `$3`, etc.

### `PgSearch.fts_name_description_match/1` — Ecto dynamic helper

For contexts that build queries with Ecto (not raw SQL), this returns a `dynamic/2` expression applying the prefix-aware tsquery to `name` and `description` columns:

```elixir
where(base_query, [s], ^PgSearch.fts_name_description_match(search_query))
where(base_query, [s, a], ^PgSearch.fts_name_description_match(search_query))
```

The first binding (`s`) must have `name` and `description` columns. The second binding is ignored by the fragment.

---

## Where search is used

### Notes — `EyeInTheSkyWeb.Notes.search_notes/3`

```elixir
Notes.search_notes(query, agent_ids, opts)
```

Searches `title` and `body` columns. Supports scoping to a project context:

| Option | Type | Description |
|---|---|---|
| `agent_ids` | list of integers | Restrict to notes parented to these agents |
| `:project_id` | integer | Also include notes parented to this project |
| `:session_ids` | list of integers | Also include notes parented to these sessions |
| `:starred` | boolean | Restrict to starred notes (pushed into SQL, not post-filtered) |
| `:limit` | integer | Max results (default 50) |

Without scope options, all notes are searched globally (used by the overview page and REST API).

**Callers:**

| Location | Scope |
|---|---|
| `OverviewLive.Notes` | Global — no scope |
| `ProjectLive.Notes` | Project + its agents + their sessions |
| `GET /api/v1/notes/search` | Global — no scope |

**Scope internals:**

Two parallel filters are built from the same scope inputs — one for the FTS path (raw SQL `AND` clause) and one for the ILIKE fallback (Ecto `dynamic`). Both build OR conditions across parent types:

```sql
AND (
  (n.parent_type IN ('project', 'projects') AND n.parent_id = $2)
  OR (n.parent_type IN ('agent', 'agents') AND n.parent_id IN ($3, $4))
  OR (n.parent_type IN ('session', 'sessions') AND n.parent_id IN ($5, $6))
)
```

The starred filter adds `AND n.starred = $N` at the end of the scope clause; the param index is computed from the number of scope params already in use.

### Tasks — `EyeInTheSkyWeb.Tasks.search_tasks/2`

```elixir
Tasks.search_tasks(query, project_id \\ nil)
```

Searches `title` and `description` columns. Optionally scoped to a project via `AND t.project_id = $2`. Preloads `:state`, `:tags`, `:sessions`, `:checklist_items`.

**Callers:** `ProjectLive.Tasks`, `ProjectLive.Kanban`, `OverviewLive.Tasks`, `GET /api/v1/tasks/search`.

### Sessions — `EyeInTheSkyWeb.Sessions` (via `fts_name_description_match`)

Sessions search uses `fts_name_description_match` directly inside Ecto query pipelines rather than `search_for`. It matches on the session's `name` and `description` columns.

Used in `list_sessions/2` and `base_session_overview_query/1` when a `search_query` option is provided.

### Prompts — `EyeInTheSkyWeb.Prompts`

Searches `name`, `description`, and `prompt_text` across the `subagent_prompts` table. Optionally scoped to a project (includes global prompts where `project_id IS NULL`).

---

## Adding search to a new context

1. Call `PgSearch.search_for/2` from your context module.
2. Pass `table:` and `search_columns:` matching your DB table/columns.
3. Build `sql_filter:` + `sql_params:` for any scope constraints (params start at `$2`).
4. Build `extra_where:` as an Ecto `dynamic` with the same logic — this covers the ILIKE fallback path.
5. Both filters must express the same constraint or the two paths will return different result sets.

```elixir
# Example: search a hypothetical "events" table scoped to a project
PgSearch.search_for(query,
  table: "events",
  schema: Event,
  search_columns: ["title", "description"],
  sql_filter: "AND e.project_id = $2",
  sql_params: [project_id],
  extra_where: dynamic([e], e.project_id == ^project_id),
  order_by: [desc: :occurred_at]
)
```

### Injection safety

Table names and column names are validated against `@safe_identifier` (`^[a-z][a-z0-9_]*$`) before being interpolated into the SQL string. If validation fails, the search falls back to the ILIKE query. Never pass user-controlled values as `table:` or `search_columns:`.

Search query values (`$1` and `sql_params`) are always parameterized — never interpolated.

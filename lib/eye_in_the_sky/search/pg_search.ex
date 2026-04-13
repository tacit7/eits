defmodule EyeInTheSky.Search.PgSearch do
  @moduledoc """
  Reusable full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback.

  Replaces the previous SQLite FTS5 implementation. Uses a prefix-aware tsquery
  so that partial last words (e.g. "plural fo") match full lexemes ("form").
  Falls back to ILIKE when the FTS query errors.
  """

  import Ecto.Query, warn: false
  alias Ecto.Adapters.SQL
  alias EyeInTheSky.Repo

  # Only lowercase letters, digits, and underscores — no injection vectors
  @safe_identifier ~r/^[a-z][a-z0-9_]*$/

  # Prefix-aware tsquery CASE expression (parameterized with $1 for raw SQL).
  # - All-special-char last word: plain plainto_tsquery (safe fallback)
  # - Single word: OR between plainto (handles dotted identifiers) and to_tsquery(:*)
  # - Multi-word: plainto for complete words AND to_tsquery(:*) for the last word
  @tsquery_case_sql """
  CASE
    WHEN length(regexp_replace(lower(regexp_replace(trim($1), '^.*\\s', '')), '[^a-z0-9]', '', 'g')) = 0
      THEN plainto_tsquery('english', $1)
    WHEN position(' ' IN trim($1)) = 0
      THEN plainto_tsquery('english', $1)
        || to_tsquery('simple', regexp_replace(lower(trim($1)), '[^a-z0-9]', '', 'g') || ':*')
    ELSE
      plainto_tsquery('english',
        left(trim($1), length(trim($1)) - length(regexp_replace(trim($1), '^.*\\s', ''))))
      && to_tsquery('simple',
        regexp_replace(lower(regexp_replace(trim($1), '^.*\\s', '')), '[^a-z0-9]', '', 'g') || ':*')
  END
  """

  # Full fragment for use in fts_name_description_match/1.
  # Ecto fragment/1 requires a compile-time string literal or module attribute as first arg.
  # The 11 ? positions: s (?.name), s (?.description), then search_query × 9.
  @fts_name_description_fragment "to_tsvector('english', coalesce(?.name, '') || ' ' || coalesce(?.description, '')) @@ (CASE WHEN length(regexp_replace(lower(regexp_replace(trim(?), '^.*\\s', '')), '[^a-z0-9]', '', 'g')) = 0 THEN plainto_tsquery('english', ?) WHEN position(' ' IN trim(?)) = 0 THEN plainto_tsquery('english', ?) || to_tsquery('simple', regexp_replace(lower(trim(?)), '[^a-z0-9]', '', 'g') || ':*') ELSE plainto_tsquery('english', left(trim(?), length(trim(?)) - length(regexp_replace(trim(?), '^.*\\s', '')))) && to_tsquery('simple', regexp_replace(lower(regexp_replace(trim(?), '^.*\\s', '')), '[^a-z0-9]', '', 'g') || ':*') END)"

  @doc """
  Convenience wrapper around `search/1` that builds the ILIKE fallback query automatically.

  Accepts the same options as `search/1`, plus:

  - `:extra_where` - An `Ecto.Query.dynamic/2` expression ANDed onto both the ILIKE fallback
    and the FTS raw SQL path (replaces `:sql_filter`/`:sql_params`)
  - `:order_by` - Ecto order_by keyword list for the fallback query (e.g. `[desc: :created_at]`)

  The fallback is built as:
      WHERE col1 ILIKE pattern OR col2 ILIKE pattern [AND extra_where] ORDER BY order_by

  The FTS SQL path derives the WHERE clause and params from `extra_where` automatically,
  eliminating the need for manually-indexed `:sql_filter`/`:sql_params`.
  """
  def search_for(query, opts) when is_binary(query) do
    schema = Keyword.fetch!(opts, :schema)
    search_columns = Keyword.fetch!(opts, :search_columns)
    order_by = Keyword.get(opts, :order_by, [])
    extra_where = Keyword.get(opts, :extra_where)

    pattern = "%#{query}%"
    column_atoms = Enum.map(search_columns, &String.to_existing_atom/1)

    fallback_query =
      Enum.reduce(column_atoms, from(s in schema), fn col, acc ->
        or_where(acc, [s], ilike(field(s, ^col), ^pattern))
      end)

    fallback_query =
      if extra_where do
        where(fallback_query, ^extra_where)
      else
        fallback_query
      end

    fallback_query =
      if order_by != [] do
        order_by(fallback_query, ^order_by)
      else
        fallback_query
      end

    # Derive sql_filter + sql_params from extra_where so callers no longer need to
    # maintain a parallel raw-SQL representation of the same predicate.
    opts =
      if extra_where do
        table = Keyword.get(opts, :table, "")
        {sql_filter, sql_params} = extra_where_to_sql(schema, extra_where, table)
        Keyword.merge(opts, sql_filter: sql_filter, sql_params: sql_params)
      else
        opts
      end

    search(Keyword.merge(opts, query: query, fallback_query: fallback_query))
  end

  # Converts an Ecto dynamic expression into a raw SQL AND-clause and param list
  # suitable for embedding in the FTS CTE query.
  #
  # Strategy: build a minimal Ecto query with just `where: ^dynamic`, call
  # `Repo.to_sql/2` to get the PostgreSQL SQL + params, extract the WHERE
  # clause text, then:
  #   1. Replace Ecto's binding alias (always "n0" since we use `from(n in ...)`)
  #      with the FTS query's table alias (first letter of the table name).
  #   2. Renumber all $N placeholders by +1 (since $1 is already taken by the
  #      FTS search term in the outer CTE query).
  defp extra_where_to_sql(schema, dynamic, table) do
    base = from(n in schema, where: ^dynamic)

    {sql, params} = Repo.to_sql(:all, base)

    # Extract everything after "WHERE" in the generated SQL.
    # Ecto generates: SELECT ... FROM "table" AS n0 WHERE n0."col" = $1 ...
    case Regex.run(~r/\bWHERE\b(.+?)(?:\s*ORDER\s+BY|\s*LIMIT|\s*$)/si, sql, capture: :all_but_first) do
      [where_clause] ->
        # Replace Ecto's "n0" alias with the FTS alias (first letter of table name).
        # The FTS query uses `String.first(table)` as its alias, so "notes" → "n".
        fts_alias = if table != "", do: String.first(table), else: "n"
        aliased_clause = String.replace(String.trim(where_clause), ~r/\bn0\b/, fts_alias)

        # Ecto numbers its params starting at $1; we need to offset by 1 since
        # the FTS CTE already uses $1 for the search term.
        shifted_clause = Regex.replace(~r/\$(\d+)/, aliased_clause, fn _, n ->
          "$#{String.to_integer(n) + 1}"
        end)

        {"AND (#{shifted_clause})", params}

      nil ->
        {"", []}
    end
  end

  @doc """
  Performs PostgreSQL full-text search with fallback to ILIKE queries.

  ## Options

  - `:table` - Main table name (required)
  - `:schema` - Ecto schema module (required)
  - `:query` - Search query string (required)
  - `:search_columns` - List of column names to search (required)
  - `:fallback_query` - Ecto query for ILIKE fallback (required)
  - `:preload` - Associations to preload (optional, default: [])

  ## Deprecated Options (kept for backwards compatibility, do not use in new code)

  - `:sql_filter` - Raw SQL WHERE clause with manual $N params. Use `:extra_where` via `search_for/2` instead.
  - `:sql_params` - Parameters for `:sql_filter`. Derived automatically when using `:extra_where`.
  - `:fts_table` - No longer used (PostgreSQL doesn't need separate FTS tables)
  - `:join_key` - No longer used
  """
  def search(opts) do
    table = Keyword.fetch!(opts, :table)
    schema = Keyword.fetch!(opts, :schema)
    query = Keyword.fetch!(opts, :query)
    search_columns = Keyword.fetch!(opts, :search_columns)
    sql_filter = Keyword.get(opts, :sql_filter, "")
    sql_params = Keyword.get(opts, :sql_params, [])
    fallback_query = Keyword.fetch!(opts, :fallback_query)
    preloads = Keyword.get(opts, :preload, [])
    limit = Keyword.get(opts, :limit)

    if safe_identifier?(table) and Enum.all?(search_columns, &safe_identifier?/1) do
      pg_fts_search(
        table,
        schema,
        query,
        search_columns,
        sql_filter,
        sql_params,
        fallback_query,
        preloads,
        limit
      )
    else
      run_fallback(fallback_query, preloads, limit)
    end
  end

  @doc """
  Returns an Ecto subquery of session IDs whose messages match the given full-text search query.

  Filters to user/agent/assistant messages to avoid tool output noise.
  ("agent" is the primary role for assistant outputs in this codebase, but "assistant" is included
  for completeness.) Excludes "tool" and "system" roles.
  Uses the GIN index on `to_tsvector('english', COALESCE(body, ''))`.

  Returns a composable query — call `subquery/1` on the result or use it directly
  in an `in` clause: `s.id in subquery(PgSearch.message_fts_session_ids(q))`.
  """
  def message_fts_session_ids(query) do
    from(m in EyeInTheSky.Messages.Message,
      where: m.sender_role in ["user", "agent", "assistant"],
      where:
        fragment(
          "to_tsvector('english', COALESCE(?, '')) @@ plainto_tsquery('english', ?)",
          m.body,
          ^query
        ),
      select: m.session_id
    )
  end

  @doc """
  Returns a dynamic Ecto expression that matches rows where the tsvector of
  `name || description` satisfies a prefix-aware tsquery for `search_query`.

  Partial last words are matched via `to_tsquery(:*)` prefix, so "session li"
  matches rows containing "list". Dotted identifiers still work via plainto_tsquery.

  The first named binding (`s`) must be the schema with `name` and `description` columns:

      where(query, [s], ^PgSearch.fts_name_description_match(search_query))
      where(query, [s, a], ^PgSearch.fts_name_description_match(search_query))
  """
  def fts_name_description_match(search_query) do
    dynamic(
      [s],
      fragment(
        @fts_name_description_fragment,
        s,
        s,
        ^search_query,
        ^search_query,
        ^search_query,
        ^search_query,
        ^search_query,
        ^search_query,
        ^search_query,
        ^search_query,
        ^search_query
      )
    )
  end

  defp safe_identifier?(value), do: Regex.match?(@safe_identifier, value)

  defp run_fallback(fallback_query, preloads, limit) do
    effective_limit = limit || 50

    query_result = limit(fallback_query, ^effective_limit)

    query_result =
      if preloads != [], do: preload(query_result, ^preloads), else: query_result

    Repo.all(query_result)
  end

  defp pg_fts_search(
         table,
         schema,
         query,
         search_columns,
         sql_filter,
         sql_params,
         fallback_query,
         preloads,
         limit
       ) do
    alias_letter = String.first(table)

    # Build tsvector expression from search columns:
    # to_tsvector('english', coalesce(col1,'') || ' ' || coalesce(col2,''))
    tsvector_expr =
      Enum.map_join(search_columns, " || ' ' || ", fn col ->
        "coalesce(#{alias_letter}.#{col}, '')"
      end)

    effective_limit = if is_integer(limit) and limit > 0, do: limit, else: 50

    # $1 = search query, trailing param = limit — never interpolated into SQL.
    limit_placeholder = "$#{length(sql_params) + 2}"

    # CTE pre-computes the tsquery once; WHERE and ORDER BY reference it without re-evaluation.
    sql = """
    WITH _q AS (SELECT (#{@tsquery_case_sql}) AS tsq)
    SELECT #{alias_letter}.*
    FROM #{table} #{alias_letter}, _q
    WHERE to_tsvector('english', #{tsvector_expr}) @@ _q.tsq
    #{sql_filter}
    ORDER BY ts_rank(to_tsvector('english', #{tsvector_expr}), _q.tsq) DESC
    LIMIT #{limit_placeholder}
    """

    params = [query | sql_params] ++ [effective_limit]

    case SQL.query(Repo, sql, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        results =
          Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Map.new()
            |> then(&Repo.load(schema, &1))
          end)

        if preloads != [] do
          Repo.preload(results, preloads)
        else
          results
        end

      {:error, _} ->
        run_fallback(fallback_query, preloads, limit)
    end
  end
end

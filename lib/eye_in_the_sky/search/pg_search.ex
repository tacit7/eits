defmodule EyeInTheSky.Search.PgSearch do
  @moduledoc """
  Reusable full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback.

  Replaces the previous SQLite FTS5 implementation. Uses a prefix-aware tsquery
  so that partial last words (e.g. "plural fo") match full lexemes ("form").
  Falls back to ILIKE when the FTS query errors.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias Ecto.Adapters.SQL

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

  - `:extra_where` - An `Ecto.Query.dynamic/2` expression ANDed onto the ILIKE fallback
  - `:order_by` - Ecto order_by keyword list for the fallback query (e.g. `[desc: :created_at]`)

  The fallback is built as:
      WHERE col1 ILIKE pattern OR col2 ILIKE pattern [AND extra_where] ORDER BY order_by
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

    search(Keyword.merge(opts, query: query, fallback_query: fallback_query))
  end

  @doc """
  Performs PostgreSQL full-text search with fallback to ILIKE queries.

  ## Options

  - `:table` - Main table name (required)
  - `:schema` - Ecto schema module (required)
  - `:query` - Search query string (required)
  - `:search_columns` - List of column names to search (required)
  - `:sql_filter` - Additional SQL WHERE clause (optional, use $N params starting after search param)
  - `:sql_params` - Parameters for SQL filter (optional, default: [])
  - `:fallback_query` - Ecto query for ILIKE fallback (required)
  - `:preload` - Associations to preload (optional, default: [])

  ## Deprecated Options (ignored, kept for backwards compatibility)

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

    # Build tsvector expression from search columns: to_tsvector('english', coalesce(col1,'') || ' ' || coalesce(col2,''))
    tsvector_expr =
      Enum.map_join(search_columns, " || ' ' || ", fn col ->
        "coalesce(#{alias_letter}.#{col}, '')"
      end)

    effective_limit = limit || 50

    # CTE pre-computes the tsquery once; WHERE and ORDER BY reference it without re-evaluation.
    sql = """
    WITH _q AS (SELECT (#{@tsquery_case_sql}) AS tsq)
    SELECT #{alias_letter}.*
    FROM #{table} #{alias_letter}, _q
    WHERE to_tsvector('english', #{tsvector_expr}) @@ _q.tsq
    #{sql_filter}
    ORDER BY ts_rank(to_tsvector('english', #{tsvector_expr}), _q.tsq) DESC
    LIMIT #{effective_limit}
    """

    params = [query | sql_params]

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

defmodule EyeInTheSkyWeb.Search.FTS5 do
  @moduledoc """
  Reusable full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback.

  Replaces the previous SQLite FTS5 implementation. Uses plainto_tsquery for
  user-friendly search (no special syntax required) and ts_rank for relevance ordering.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo

  # Only lowercase letters, digits, and underscores — no injection vectors
  @safe_identifier ~r/^[a-z][a-z0-9_]*$/

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

    search(opts ++ [fallback_query: fallback_query])
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
      search_columns
      |> Enum.map(fn col -> "coalesce(#{alias_letter}.#{col}, '')" end)
      |> Enum.join(" || ' ' || ")

    effective_limit = limit || 50

    sql = """
    SELECT #{alias_letter}.*
    FROM #{table} #{alias_letter}
    WHERE to_tsvector('english', #{tsvector_expr}) @@ plainto_tsquery('english', $1)
    #{sql_filter}
    ORDER BY ts_rank(to_tsvector('english', #{tsvector_expr}), plainto_tsquery('english', $1)) DESC
    LIMIT #{effective_limit}
    """

    params = [query | sql_params]

    case Ecto.Adapters.SQL.query(Repo, sql, params) do
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

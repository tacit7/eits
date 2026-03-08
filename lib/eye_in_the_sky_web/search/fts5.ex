defmodule EyeInTheSkyWeb.Search.FTS5 do
  @moduledoc """
  Reusable full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback.

  Replaces the previous SQLite FTS5 implementation. Uses plainto_tsquery for
  user-friendly search (no special syntax required) and ts_rank for relevance ordering.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo

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

  ## Examples

      FTS5.search(
        table: "tasks",
        schema: Task,
        query: "bug fix",
        search_columns: ["title", "description"],
        sql_filter: "AND t.project_id = $2",
        sql_params: [project_id],
        fallback_query: from(t in Task, where: ilike(t.title, ^pattern)),
        preload: [:state, :tags]
      )
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

    pg_fts_search(table, schema, query, search_columns, sql_filter, sql_params, fallback_query, preloads)
  end

  defp pg_fts_search(table, schema, query, search_columns, sql_filter, sql_params, fallback_query, preloads) do
    alias_letter = String.first(table)

    # Build tsvector expression from search columns: to_tsvector('english', coalesce(col1,'') || ' ' || coalesce(col2,''))
    tsvector_expr =
      search_columns
      |> Enum.map(fn col -> "coalesce(#{alias_letter}.#{col}, '')" end)
      |> Enum.join(" || ' ' || ")

    sql = """
    SELECT #{alias_letter}.*
    FROM #{table} #{alias_letter}
    WHERE to_tsvector('english', #{tsvector_expr}) @@ plainto_tsquery('english', $1)
    #{sql_filter}
    ORDER BY ts_rank(to_tsvector('english', #{tsvector_expr}), plainto_tsquery('english', $1)) DESC
    LIMIT 50
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
        # Fallback to ILIKE search
        query_result =
          fallback_query
          |> limit(50)

        query_result =
          if preloads != [] do
            preload(query_result, ^preloads)
          else
            query_result
          end

        Repo.all(query_result)
    end
  end
end

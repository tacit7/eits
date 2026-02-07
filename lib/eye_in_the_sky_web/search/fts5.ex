defmodule EyeInTheSkyWeb.Search.FTS5 do
  @moduledoc """
  Reusable FTS5 full-text search with LIKE fallback.

  Extracts common pattern used across prompts, tasks, and notes contexts.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo

  @doc """
  Performs FTS5 search with fallback to LIKE queries.

  ## Options

  - `:table` - Main table name (required)
  - `:fts_table` - FTS5 search table name (required)
  - `:schema` - Ecto schema module (required)
  - `:query` - Search query string (required)
  - `:join_key` - FTS column to join on main table id (e.g. "task_id"). Defaults to "rowid"
  - `:sql_filter` - Additional SQL WHERE clause (optional)
  - `:sql_params` - Parameters for SQL filter (optional, default: [])
  - `:fallback_query` - Ecto query for LIKE fallback (required)
  - `:preload` - Associations to preload (optional, default: [])

  ## Examples

      FTS5.search(
        table: "tasks",
        fts_table: "task_search",
        schema: Task,
        query: "bug fix",
        sql_filter: "AND t.project_id = ?",
        sql_params: [project_id],
        fallback_query: from(t in Task, where: ilike(t.title, ^pattern)),
        preload: [:state, :tags]
      )
  """
  def search(opts) do
    table = Keyword.fetch!(opts, :table)
    fts_table = Keyword.fetch!(opts, :fts_table)
    schema = Keyword.fetch!(opts, :schema)
    query = Keyword.fetch!(opts, :query)
    join_key = Keyword.get(opts, :join_key, "rowid")
    sql_filter = Keyword.get(opts, :sql_filter, "")
    sql_params = Keyword.get(opts, :sql_params, [])
    fallback_query = Keyword.fetch!(opts, :fallback_query)
    preloads = Keyword.get(opts, :preload, [])

    fts5_search(
      table,
      fts_table,
      schema,
      query,
      join_key,
      sql_filter,
      sql_params,
      fallback_query,
      preloads
    )
  end

  defp fts5_search(table, fts_table, schema, query, join_key, sql_filter, sql_params, fallback_query, preloads) do
    # Use table alias for cleaner SQL
    alias_letter = String.first(table)

    sql = """
    SELECT #{alias_letter}.*
    FROM #{table} #{alias_letter}
    JOIN #{fts_table} fts ON #{alias_letter}.id = fts.#{join_key}
    WHERE fts.#{fts_table} MATCH ?
    #{sql_filter}
    ORDER BY fts.rank
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
        # Fallback to LIKE search
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

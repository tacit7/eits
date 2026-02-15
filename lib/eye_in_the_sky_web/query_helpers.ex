defmodule EyeInTheSkyWeb.QueryHelpers do
  @moduledoc """
  Reusable query helpers for common patterns across contexts.

  Reduces duplication in session-scoped queries, counting, and upsert operations.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo

  @doc """
  Lists records for a session using direct foreign key.

  Supports optional limit and custom ordering.

  ## Examples

      iex> for_session_direct(Commit, "session-123", limit: 10)
      [%Commit{}, ...]

      iex> for_session_direct(Log, "session-456", order_by: [asc: :inserted_at])
      [%Log{}, ...]
  """
  def for_session_direct(queryable, session_id, opts \\ []) do
    limit_val = Keyword.get(opts, :limit)
    order = Keyword.get(opts, :order_by, desc: :inserted_at)
    preloads = Keyword.get(opts, :preload, [])

    query =
      queryable
      |> where([x], x.session_id == ^session_id)
      |> order_by(^order)

    query = if limit_val, do: limit(query, ^limit_val), else: query
    query = if preloads != [], do: preload(query, ^preloads), else: query

    Repo.all(query)
  end

  @doc """
  Lists records for a session using join table pattern.

  Used for many-to-many relationships like tasks <-> sessions.

  ## Examples

      iex> for_session_join(Task, "session-123", "task_sessions", preload: [:state, :tags])
      [%Task{}, ...]
  """
  def for_session_join(queryable, session_id, join_table, opts \\ []) do
    limit_val = Keyword.get(opts, :limit)
    order = Keyword.get(opts, :order_by, desc: :inserted_at)
    preloads = Keyword.get(opts, :preload, [])

    query =
      queryable
      |> join(:inner, [x], j in ^join_table, on: j.task_id == x.id)
      |> where([x, j], j.session_id == ^session_id)
      |> order_by([x], ^order)

    query = if limit_val, do: limit(query, ^limit_val), else: query
    query = if preloads != [], do: preload(query, ^preloads), else: query

    Repo.all(query)
  end

  @doc """
  Counts records for a session using direct foreign key.

  ## Examples

      iex> count_for_session(Commit, "session-123")
      42
  """
  def count_for_session(queryable, session_id) do
    queryable
    |> where([x], x.session_id == ^session_id)
    |> select([x], count(x.id))
    |> Repo.one() || 0
  end

  @doc """
  Counts records for a session using join table pattern.

  ## Examples

      iex> count_for_session_join(Task, "session-123", "task_sessions")
      15
  """
  def count_for_session_join(queryable, session_id, join_table) do
    queryable
    |> join(:inner, [x], j in ^join_table, on: j.task_id == x.id)
    |> where([x, j], j.session_id == ^session_id)
    |> select([x], count(x.id))
    |> Repo.one() || 0
  end

  @doc """
  Upsert pattern: Get existing record or create new one.

  Calls get_fn to fetch existing record. If nil, inserts. Otherwise updates.

  ## Examples

      iex> upsert(SessionContext, fn -> get_context(session_id) end, %{session_id: "123", context: "..."})
      {:ok, %SessionContext{}}
  """
  def upsert(schema, get_fn, attrs) when is_function(get_fn, 0) do
    case get_fn.() do
      nil ->
        struct(schema)
        |> schema.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> schema.changeset(attrs)
        |> Repo.update()
    end
  end
end

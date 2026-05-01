defmodule EyeInTheSky.Logs do
  @moduledoc """
  The Logs context for managing logs and session logs.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Logs.{Log, SessionLog}
  alias EyeInTheSky.QueryHelpers
  alias EyeInTheSky.Repo

  # Log functions

  @doc """
  Returns the list of logs for a specific session.
  """
  def list_logs_for_session(session_id, opts \\ []) do
    QueryHelpers.for_session_direct(Log, session_id,
      order_by: [desc: :timestamp],
      limit: Keyword.get(opts, :limit)
    )
  end

  @doc """
  Returns recent logs for a session with a limit.
  """
  def list_recent_logs(session_id, limit \\ 50) do
    list_logs_for_session(session_id, limit: limit)
  end

  @doc """
  Counts logs for a specific session.
  """
  def count_logs_for_session(session_id) do
    QueryHelpers.count_for_session(Log, session_id)
  end

  @doc """
  Filters logs by type. Default limit is 500; pass `limit:` opt to override.
  """
  def filter_logs_by_type(session_id, type, opts \\ []) do
    Log
    |> where([l], l.session_id == ^session_id and l.type == ^type)
    |> order_by([l], desc: l.timestamp)
    |> limit(^Keyword.get(opts, :limit, 500))
    |> Repo.all()
  end

  @doc """
  Gets a single log.
  """
  def get_log!(id) do
    Repo.get!(Log, id)
  end

  @doc """
  Creates a log.
  """
  def create_log(attrs \\ %{}) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  # SessionLog functions

  @doc """
  Returns the list of session logs for a specific session. Default limit is 500.
  """
  def list_session_logs_for_session(session_id, opts \\ []) do
    SessionLog
    |> where([sl], sl.session_id == ^session_id)
    |> order_by([sl], desc: sl.timestamp)
    |> limit(^Keyword.get(opts, :limit, 500))
    |> Repo.all()
  end

  @doc """
  Filters session logs by log level. Default limit is 500.
  """
  def filter_session_logs_by_level(session_id, log_level, opts \\ []) do
    SessionLog
    |> where([sl], sl.session_id == ^session_id and sl.log_level == ^log_level)
    |> order_by([sl], desc: sl.timestamp)
    |> limit(^Keyword.get(opts, :limit, 500))
    |> Repo.all()
  end

  @doc """
  Creates a session log.
  """
  def create_session_log(attrs \\ %{}) do
    %SessionLog{}
    |> SessionLog.changeset(attrs)
    |> Repo.insert()
  end
end

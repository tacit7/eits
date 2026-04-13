defmodule EyeInTheSky.Sessions.Loader do
  @moduledoc """
  Multi-query data loading functions for session detail views.

  WARNING: Functions in this module issue 5+ sequential DB queries each.
  They are intended exclusively for single-session detail pages.
  Do NOT call these from list views, overview pages, or any context
  where multiple sessions are rendered — it will cause N+1 query problems.
  """

  @doc """
  Loads associated data for a specific session detail view.

  Intended for single-session detail pages only. Do NOT use for list views
  or anywhere multiple sessions are rendered — it issues one query per
  association.

  ## Options

    - `:tasks_limit` / `:tasks_offset` — paginate tasks
    - `:commits_limit` / `:commits_offset` — paginate commits
    - `:logs_limit` / `:logs_offset` — paginate logs
    - `:notes_limit` / `:notes_offset` — paginate notes

  ## Examples

      iex> load_session_data("abc-123")
      %{tasks: [...], commits: [...], ...}

      iex> load_session_data("abc-123", tasks_limit: 20, logs_limit: 50, logs_offset: 50)
      %{tasks: [...], ...}

  """
  def load_session_data(session_id, opts \\ []) do
    alias EyeInTheSky.{Commits, Contexts, Logs, Notes, Tasks}

    %{
      tasks:
        Tasks.list_tasks_for_session(session_id,
          limit: Keyword.get(opts, :tasks_limit),
          offset: Keyword.get(opts, :tasks_offset)
        ),
      commits:
        Commits.list_commits_for_session(session_id,
          limit: Keyword.get(opts, :commits_limit),
          offset: Keyword.get(opts, :commits_offset)
        ),
      logs:
        Logs.list_logs_for_session(session_id,
          limit: Keyword.get(opts, :logs_limit),
          offset: Keyword.get(opts, :logs_offset)
        ),
      notes:
        Notes.list_notes_for_session(session_id,
          limit: Keyword.get(opts, :notes_limit),
          offset: Keyword.get(opts, :notes_offset)
        ),
      session_context:
        case Contexts.get_session_context(session_id) do
          {:ok, ctx} -> ctx
          {:error, :not_found} -> nil
        end,
      metrics: nil
    }
  end

  @doc """
  Gets counts for all tabs (cheap aggregate queries).
  """
  def get_session_counts(session_id) do
    alias EyeInTheSky.{Commits, Logs, Messages, Notes, Tasks}

    %{
      tasks: Tasks.count_tasks_for_session(session_id),
      commits: Commits.count_commits_for_session(session_id),
      logs: Logs.count_logs_for_session(session_id),
      notes: Notes.count_notes_for_session(session_id),
      messages: Messages.count_messages_for_session(session_id)
    }
  end
end

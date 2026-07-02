defmodule EyeInTheSky.Sessions.StatusTransitions do
  @moduledoc """
  Status transition and state-changing operations for sessions.

  Handles archival, deletion, and status updates that modify session state.
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.Events
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions.Session

  @doc """
  Sets a session to idle status and fires agent_stopped event.
  Used by cancel/stop handlers in the web layer.
  """
  def set_session_idle(%Session{} = session) do
    with {:ok, updated} <- update_session_internal(session, %{status: "idle"}) do
      Events.agent_stopped(updated)
      {:ok, updated}
    end
  end

  @doc """
  Ends a session by setting ended_at timestamp.
  Broadcasts agent_stopped and session_updated events.
  """
  def end_session(%Session{} = session, opts \\ %{}) do
    attrs = %{ended_at: DateTime.utc_now()}
    attrs = if s = opts[:summary], do: Map.put(attrs, :description, s), else: attrs
    final_status = opts[:final_status] || "completed"
    attrs = Map.put(attrs, :status, final_status)

    with {:ok, updated} <- update_session_internal(session, attrs) do
      Events.agent_stopped(updated)
      Events.session_updated(updated)
      {:ok, updated}
    end
  end

  @doc """
  Archives a session (soft delete).
  Broadcasts session_updated event.
  """
  def archive_session(%Session{} = session), do: set_archived(session, DateTime.utc_now())

  @doc """
  Unarchives a session.
  Broadcasts session_updated event.
  """
  def unarchive_session(%Session{} = session), do: set_archived(session, nil)

  @doc """
  Deletes a session (hard delete).
  """
  def delete_session(%Session{} = session), do: Repo.delete(session)

  @doc """
  Deletes multiple sessions by their integer IDs in a single query.
  Returns `{deleted_count, nil}`.
  """
  def batch_delete_sessions(ids) when is_list(ids) do
    Repo.delete_all(from s in Session, where: s.id in ^ids)
  end

  @doc """
  Batch-archives sessions by integer IDs in a single query.
  Only archives sessions belonging to the given project_id (ownership check).
  Returns `{archived_count, nil}`.
  """
  def batch_archive_sessions_for_project(ids, project_id) when is_list(ids) and ids != [] do
    Repo.update_all(
      from(s in Session,
        where: s.id in ^ids and s.project_id == ^project_id
      ),
      set: [archived_at: DateTime.utc_now()]
    )
  end

  def batch_archive_sessions_for_project([], _project_id), do: {0, nil}

  # --- Private Helpers ---

  defp update_session_internal(%Session{} = session, attrs) do
    # Remove model fields if present - they are immutable
    attrs =
      attrs
      |> Map.delete(:model_provider)
      |> Map.delete(:model_name)
      |> Map.delete(:model_version)

    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  defp set_archived(%Session{} = session, value) do
    with {:ok, updated} <- update_session_internal(session, %{archived_at: value}) do
      Events.session_updated(updated)
      {:ok, updated}
    end
  end
end

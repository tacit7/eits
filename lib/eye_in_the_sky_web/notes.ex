defmodule EyeInTheSkyWeb.Notes do
  @moduledoc """
  The Notes context for managing notes.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Notes.Note
  alias EyeInTheSkyWeb.Search.FTS5

  @doc """
  Returns the list of notes.
  """
  def list_notes do
    Repo.all(Note)
  end

  @doc """
  Returns notes for a specific session.
  Handles both "session" and "sessions" parent_type for backwards compatibility.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def list_notes_for_session(session_id) do
    # Get session to access both id and uuid
    session = Repo.get(EyeInTheSkyWeb.ExecutionAgents.ExecutionAgent, session_id)

    if session do
      Note
      |> where([n], n.parent_type in ["session", "sessions"] and
                    (n.parent_id == ^to_string(session_id) or n.parent_id == ^session.uuid))
      |> order_by([n], desc: n.created_at)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Counts notes for a specific session.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def count_notes_for_session(session_id) do
    session = Repo.get(EyeInTheSkyWeb.ExecutionAgents.ExecutionAgent, session_id)

    if session do
      Note
      |> where([n], n.parent_type in ["session", "sessions"] and
                    (n.parent_id == ^to_string(session_id) or n.parent_id == ^session.uuid))
      |> Repo.aggregate(:count, :id)
    else
      0
    end
  end

  @doc """
  Returns notes for a specific agent.
  Handles both "agent" and "agents" parent_type for backwards compatibility.
  """
  def list_notes_for_agent(agent_id) do
    agent = Repo.get(EyeInTheSkyWeb.ChatAgents.ChatAgent, agent_id)

    if agent do
      Note
      |> where([n], n.parent_type in ["agent", "agents"] and
                    (n.parent_id == ^to_string(agent_id) or n.parent_id == ^agent.uuid))
      |> order_by([n], desc: n.created_at)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Returns notes for a specific task.
  Handles both "task" and "tasks" parent_type for backwards compatibility.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def list_notes_for_task(task_id) do
    task = Repo.get(EyeInTheSkyWeb.Tasks.Task, task_id)

    if task do
      Note
      |> where([n], n.parent_type in ["task", "tasks"] and
                    (n.parent_id == ^to_string(task_id) or n.parent_id == ^task.uuid))
      |> order_by([n], desc: n.created_at)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Gets a single note.
  """
  def get_note!(id) do
    Repo.get!(Note, id)
  end

  @doc """
  Creates a note.
  """
  def create_note(attrs \\ %{}) do
    %Note{}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a note.
  """
  def delete_note(%Note{} = note) do
    Repo.delete(note)
  end

  @doc """
  Toggles the starred status of a note.
  """
  def toggle_starred(note_id) do
    note = get_note!(note_id)
    new_starred = if note.starred == 1, do: 0, else: 1

    note
    |> Ecto.Changeset.change(starred: new_starred)
    |> Repo.update()
  end

  @doc """
  Search notes using FTS5.
  Requires notes_fts FTS5 table in database.
  """
  def search_notes(query, agent_ids \\ []) when is_binary(query) do
    pattern = "%#{query}%"

    fallback_query =
      from n in Note,
        where: ilike(n.body, ^pattern)

    fallback_query =
      if length(agent_ids) > 0 do
        where(fallback_query, [n], n.parent_type == "agent" and n.parent_id in ^agent_ids)
      else
        fallback_query
      end
      |> order_by([n], desc: n.created_at)

    # Build SQL filter for agent_ids
    {sql_filter, sql_params} =
      if length(agent_ids) > 0 do
        placeholders = Enum.map(agent_ids, fn _ -> "?" end) |> Enum.join(",")
        {"AND n.parent_type = 'agent' AND n.parent_id IN (#{placeholders})", agent_ids}
      else
        {"", []}
      end

    FTS5.search(
      table: "notes",
      fts_table: "notes_fts",
      schema: Note,
      query: query,
      join_key: "rowid",
      sql_filter: sql_filter,
      sql_params: sql_params,
      fallback_query: fallback_query
    )
  end
end

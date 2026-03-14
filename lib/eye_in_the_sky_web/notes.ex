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
  Batch-loads annotations for a list of tasks and sets :notes and :notes_count on each.
  Notes are stored with parent_type "task"/"tasks" and parent_id as integer string or UUID.
  """
  def with_notes_count(tasks) when is_list(tasks) do
    task_int_ids = Enum.map(tasks, &to_string(&1.id))
    task_uuids = tasks |> Enum.map(& &1.uuid) |> Enum.reject(&is_nil/1)
    all_ids = task_int_ids ++ task_uuids

    notes_by_parent =
      Note
      |> where([n], n.parent_type in ["task", "tasks"])
      |> where([n], n.parent_id in ^all_ids)
      |> order_by([n], asc: n.created_at)
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)

    Enum.map(tasks, fn task ->
      notes =
        (Map.get(notes_by_parent, to_string(task.id), []) ++
           if task.uuid, do: Map.get(notes_by_parent, task.uuid, []), else: [])
        |> Enum.uniq_by(& &1.id)

      task
      |> Map.put(:notes, notes)
      |> Map.put(:notes_count, length(notes))
    end)
  end

  @doc """
  Returns notes for a specific session.
  Handles both "session" and "sessions" parent_type for backwards compatibility.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def list_notes_for_session(session_id) do
    # session_id can be a UUID string or an integer string
    session =
      case Integer.parse(to_string(session_id)) do
        {int_id, ""} -> Repo.get(EyeInTheSkyWeb.Sessions.Session, int_id)
        _ -> Repo.get_by(EyeInTheSkyWeb.Sessions.Session, uuid: session_id)
      end

    if session do
      session_int_str = to_string(session.id)

      Note
      |> where(
        [n],
        n.parent_type in ["session", "sessions"] and
          (n.parent_id == ^session_int_str or n.parent_id == ^session.uuid)
      )
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
    session = Repo.get(EyeInTheSkyWeb.Sessions.Session, session_id)

    if session do
      Note
      |> where(
        [n],
        n.parent_type in ["session", "sessions"] and
          (n.parent_id == ^to_string(session_id) or n.parent_id == ^session.uuid)
      )
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
    agent = Repo.get(EyeInTheSkyWeb.Agents.Agent, agent_id)

    if agent do
      Note
      |> where(
        [n],
        n.parent_type in ["agent", "agents"] and
          (n.parent_id == ^to_string(agent_id) or n.parent_id == ^agent.uuid)
      )
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
      uuid_filter =
        if task.uuid do
          dynamic([n], n.parent_id == ^to_string(task_id) or n.parent_id == ^task.uuid)
        else
          dynamic([n], n.parent_id == ^to_string(task_id))
        end

      Note
      |> where([n], n.parent_type in ["task", "tasks"])
      |> where(^uuid_filter)
      |> order_by([n], desc: n.created_at)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Gets a single note. Returns nil if not found.
  """
  def get_note(id) do
    Repo.get(Note, id)
  end

  @doc """
  Gets a single note. Raises if not found.
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
  def search_notes(query, agent_ids \\ [], opts \\ []) when is_binary(query) do
    agent_ids_str = Enum.map(agent_ids, &to_string/1)

    extra_where =
      if agent_ids_str != [] do
        dynamic([n], n.parent_type == "agent" and n.parent_id in ^agent_ids_str)
      end

    # Build SQL filter for agent_ids (params start at $2 since $1 is the search query)
    {sql_filter, sql_params} =
      if agent_ids_str != [] do
        placeholders =
          agent_ids_str
          |> Enum.with_index(2)
          |> Enum.map(fn {_, i} -> "$#{i}" end)
          |> Enum.join(",")

        {"AND n.parent_type = 'agent' AND n.parent_id IN (#{placeholders})", agent_ids_str}
      else
        {"", []}
      end

    FTS5.search_for(query,
      table: "notes",
      schema: Note,
      search_columns: ["title", "body"],
      sql_filter: sql_filter,
      sql_params: sql_params,
      extra_where: extra_where,
      order_by: [desc: :created_at],
      limit: Keyword.get(opts, :limit)
    )
  end
end

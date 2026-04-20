defmodule EyeInTheSky.Notes do
  @moduledoc """
  The Notes context for managing notes.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Notes.Note
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Search.PgSearch
  alias EyeInTheSky.Notes.NoteQueries
  alias EyeInTheSky.Sessions
  alias EyeInTheSky.Tasks

  # Delegate to NoteQueries to avoid a circular dependency with EyeInTheSky.Tasks.
  defdelegate with_notes_count(tasks), to: NoteQueries

  @doc """
  Returns the list of notes.
  """
  def list_notes do
    Repo.all(Note)
  end

  @doc """
  Returns notes for a specific session.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def list_notes_for_session(session_id, opts \\ []) do
    with {:ok, session} <- resolve_session(session_id) do
      session_int_str = to_string(session.id)
      limit_val = Keyword.get(opts, :limit)
      offset_val = Keyword.get(opts, :offset)

      query =
        Note
        |> scope_by_parent("session", session_int_str, session.uuid)
        |> order_by([n], desc: n.created_at)

      query = if limit_val, do: limit(query, ^limit_val), else: query
      query = if offset_val, do: offset(query, ^offset_val), else: query

      Repo.all(query)
    else
      {:error, _} -> []
    end
  end

  @doc """
  Counts notes for a specific session.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def count_notes_for_session(session_id) do
    with {:ok, session} <- resolve_session(session_id) do
      session_int_str = to_string(session.id)

      Note
      |> scope_by_parent("session", session_int_str, session.uuid)
      |> Repo.aggregate(:count, :id)
    else
      {:error, _} -> 0
    end
  end

  @doc """
  Returns notes for a specific task.
  Accepts either an integer task ID or a UUID string.
  Returns [] if the task does not exist (preserves prior behavior).
  Resolves the task via the Tasks context, then matches notes on both integer ID (as string) and UUID.
  """
  def list_notes_for_task(task_id) do
    case resolve_task_ids(task_id) do
      nil ->
        []

      {int_id, uuid} ->
        Note
        |> scope_by_parent("task", to_string(int_id), uuid)
        |> order_by([n], desc: n.created_at)
        |> Repo.all()
    end
  end

  @doc """
  Returns recent notes for a specific project, ordered by created_at desc.
  Options: `:limit` (default 5)
  """
  def list_notes_for_project(project_id, opts \\ []) do
    limit_val = Keyword.get(opts, :limit, 5)
    project_id_str = to_string(project_id)

    Note
    |> where([n], n.parent_type == "project" and n.parent_id == ^project_id_str)
    |> order_by([n], desc: n.created_at)
    |> limit(^limit_val)
    |> Repo.all()
  end

  @doc """
  List notes with filtering options. Moves query logic out of LiveViews.

  Options:
  - `:project_id` - filter by project (and its agents/sessions)
  - `:agent_ids` - list of agent IDs; session IDs are resolved internally
  - `:starred` - boolean, default false
  - `:type_filter` - "all" | "project" | "agent" | "session" | "task"
  - `:sort` - "newest" (default) | "oldest"
  - `:limit` - integer, default 200
  """
  def list_notes_filtered(opts \\ []) do
    starred_only = Keyword.get(opts, :starred, false)
    type_filter = Keyword.get(opts, :type_filter, "all")
    sort = Keyword.get(opts, :sort, "newest")
    limit_val = Keyword.get(opts, :limit, 200)
    project_id = Keyword.get(opts, :project_id)
    agent_ids = Keyword.get(opts, :agent_ids, [])

    order = if sort == "oldest", do: [asc: :created_at], else: [desc: :created_at]

    project_id_str = if project_id, do: to_string(project_id)
    agent_id_strs = Enum.map(agent_ids, &to_string/1)

    session_id_strs = session_id_strs_for_agents(agent_ids)

    base =
      if project_id_str || agent_id_strs != [] || session_id_strs != [] do
        scope = build_scope_dynamic(project_id_str, agent_id_strs, session_id_strs)
        from(n in Note, where: ^scope, order_by: ^order, limit: ^limit_val)
      else
        from(n in Note, order_by: ^order, limit: ^limit_val)
      end

    base = if starred_only, do: from(n in base, where: n.starred == true), else: base

    base =
      if type_filter != "all" do
        from(n in base, where: n.parent_type == ^type_filter)
      else
        base
      end

    Repo.all(base)
  end

  @doc """
  Gets a single note. Returns {:ok, note} if found, {:error, :not_found} otherwise.
  """
  def get_note(id) do
    case Repo.get(Note, id) do
      nil -> {:error, :not_found}
      note -> {:ok, note}
    end
  end

  @doc """
  Gets a single note. Raises if not found.
  """
  def get_note!(id) do
    Repo.get!(Note, id)
  end

  @doc """
  Builds a Note changeset without inserting. Use when composing Ecto.Multi transactions
  that need to insert a note as part of a larger transaction (e.g., complete_task).
  """
  def note_changeset(attrs \\ %{}) do
    Note.changeset(%Note{}, attrs)
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
  Updates a note's body (and optionally title).
  """
  def update_note(%Note{} = note, attrs) do
    note
    |> Ecto.Changeset.cast(attrs, [:body, :title, :starred])
    |> Ecto.Changeset.validate_required([:body])
    |> Repo.update()
  end

  @doc """
  Toggles the starred status of a note.
  """
  def toggle_starred(note_id) do
    case get_note(note_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, note} ->
        update_note(note, %{starred: !note.starred})
    end
  end

  @doc """
  Search notes using PostgreSQL full-text search.

  Options:
  - `:project_id` - restrict to notes parented to this project
  - `:session_ids` - restrict to notes parented to these sessions
  - `:starred` - when true, restrict to starred notes (pushed into query, not post-filtered)
  - `:limit` - max results
  """
  def search_notes(query, agent_ids \\ [], opts \\ []) when is_binary(query) do
    agent_ids_str = Enum.map(agent_ids, &to_string/1)
    project_id = Keyword.get(opts, :project_id)
    project_id_str = if project_id, do: to_string(project_id), else: nil
    starred_only = Keyword.get(opts, :starred, false)

    # When session_ids not provided but agent_ids are, resolve them automatically
    # so session-parented notes appear in project search scope.
    session_ids_str =
      case Keyword.get(opts, :session_ids) do
        nil -> session_id_strs_for_agents(agent_ids)
        ids -> Enum.map(ids, &to_string/1)
      end

    extra_where = build_extra_where(project_id_str, agent_ids_str, session_ids_str, starred_only)

    PgSearch.search_for(query,
      table: "notes",
      schema: Note,
      search_columns: ["title", "body"],
      extra_where: extra_where,
      order_by: [desc: :created_at],
      limit: Keyword.get(opts, :limit)
    )
  end

  defp build_extra_where(project_id_str, agent_ids_str, session_ids_str, starred_only) do
    has_scope = agent_ids_str != [] or project_id_str != nil or session_ids_str != []

    scope_dynamic =
      if has_scope, do: build_scope_dynamic(project_id_str, agent_ids_str, session_ids_str)

    case {scope_dynamic, starred_only} do
      {nil, false} -> nil
      {nil, true} -> dynamic([n], n.starred == true)
      {scope, false} -> scope
      {scope, true} -> dynamic([n], ^scope and n.starred == true)
    end
  end

  # Builds an Ecto dynamic OR filter across all parent types in scope.
  defp build_scope_dynamic(project_id_str, agent_ids_str, session_ids_str) do
    clauses =
      []
      |> maybe_add_dynamic(project_id_str != nil, fn ->
        dynamic([n], n.parent_type == "project" and n.parent_id == ^project_id_str)
      end)
      |> maybe_add_dynamic(agent_ids_str != [], fn ->
        dynamic([n], n.parent_type == "agent" and n.parent_id in ^agent_ids_str)
      end)
      |> maybe_add_dynamic(session_ids_str != [], fn ->
        dynamic([n], n.parent_type == "session" and n.parent_id in ^session_ids_str)
      end)

    Enum.reduce(clauses, fn clause, acc -> dynamic([n], ^acc or ^clause) end)
  end

  defp maybe_add_dynamic(list, false, _fun), do: list
  defp maybe_add_dynamic(list, true, fun), do: list ++ [fun.()]

  defp scope_by_parent(query, type, id_str, uuid) do
    where(query, [n], n.parent_type == ^type and (n.parent_id == ^id_str or n.parent_id == ^uuid))
  end

  defp resolve_session(session_id) do
    Sessions.resolve(to_string(session_id))
  end

  defp session_id_strs_for_agents([]), do: []

  defp session_id_strs_for_agents(agent_ids) do
    from(s in EyeInTheSky.Sessions.Session, where: s.agent_id in ^agent_ids, select: s.id)
    |> Repo.all()
    |> Enum.map(&to_string/1)
  end

  # Resolves a task identifier (integer ID or UUID string) via the Tasks context.
  # Returns {integer_id, uuid_string} or nil if the task does not exist.
  defp resolve_task_ids(task_id) do
    case Tasks.get_task_ids(task_id) do
      {:ok, ids} -> ids
      {:error, :not_found} -> nil
    end
  end
end

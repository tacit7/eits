defmodule EyeInTheSky.Notes do
  @moduledoc """
  The Notes context for managing notes.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Notes.Note
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Search.PgSearch
  alias EyeInTheSky.Sessions

  @doc """
  Returns the list of notes.
  """
  def list_notes do
    Repo.all(Note)
  end

  @doc """
  Batch-loads annotations for a list of tasks and sets :notes and :notes_count on each.
  Notes are stored with parent_type "task" and parent_id as integer string or UUID.
  """
  def with_notes_count(tasks) when is_list(tasks) do
    task_int_ids = Enum.map(tasks, &to_string(&1.id))
    task_uuids = tasks |> Enum.map(& &1.uuid) |> Enum.reject(&is_nil/1)
    all_ids = task_int_ids ++ task_uuids

    notes_by_parent =
      Note
      |> where([n], n.parent_type == "task")
      |> where([n], n.parent_id in ^all_ids)
      |> order_by([n], asc: n.created_at)
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)

    Enum.map(tasks, fn task ->
      notes =
        (Map.get(notes_by_parent, to_string(task.id), []) ++
           if(task.uuid, do: Map.get(notes_by_parent, task.uuid, []), else: []))
        |> Enum.uniq_by(& &1.id)

      task
      |> Map.put(:notes, notes)
      |> Map.put(:notes_count, length(notes))
    end)
  end

  @doc """
  Returns notes for a specific session.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def list_notes_for_session(session_id, opts \\ []) do
    # session_id can be a UUID string or an integer string
    session =
      case Sessions.resolve(to_string(session_id)) do
        {:ok, s} -> s
        _ -> nil
      end

    if session do
      session_int_str = to_string(session.id)
      limit_val = Keyword.get(opts, :limit)
      offset_val = Keyword.get(opts, :offset)

      query =
        Note
        |> where(
          [n],
          n.parent_type == "session" and
            (n.parent_id == ^session_int_str or n.parent_id == ^session.uuid)
        )
        |> order_by([n], desc: n.created_at)

      query = if limit_val, do: limit(query, ^limit_val), else: query
      query = if offset_val, do: offset(query, ^offset_val), else: query

      Repo.all(query)
    else
      []
    end
  end

  @doc """
  Counts notes for a specific session.
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def count_notes_for_session(session_id) do
    session = Repo.get(EyeInTheSky.Sessions.Session, session_id)

    if session do
      Note
      |> where(
        [n],
        n.parent_type == "session" and
          (n.parent_id == ^to_string(session_id) or n.parent_id == ^session.uuid)
      )
      |> Repo.aggregate(:count, :id)
    else
      0
    end
  end

  @doc """
  Returns notes for a specific agent.
  """
  def list_notes_for_agent(agent_id) do
    agent = Repo.get(EyeInTheSky.Agents.Agent, agent_id)

    if agent do
      Note
      |> where(
        [n],
        n.parent_type == "agent" and
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
  Matches on both integer ID (as string) and UUID for migration compatibility.
  """
  def list_notes_for_task(task_id) do
    task = Repo.get(EyeInTheSky.Tasks.Task, task_id)

    if task do
      uuid_filter =
        if task.uuid do
          dynamic([n], n.parent_id == ^to_string(task_id) or n.parent_id == ^task.uuid)
        else
          dynamic([n], n.parent_id == ^to_string(task_id))
        end

      Note
      |> where([n], n.parent_type == "task")
      |> where(^uuid_filter)
      |> order_by([n], desc: n.created_at)
      |> Repo.all()
    else
      []
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

    project_id_str = project_id && to_string(project_id)
    agent_id_strs = Enum.map(agent_ids, &to_string/1)

    session_id_strs =
      if agent_ids != [] do
        from(s in EyeInTheSky.Sessions.Session, where: s.agent_id in ^agent_ids, select: s.id)
        |> Repo.all()
        |> Enum.map(&to_string/1)
      else
        []
      end

    base =
      if project_id_str || agent_id_strs != [] || session_id_strs != [] do
        scope = build_scope_dynamic(project_id_str, agent_id_strs, session_id_strs)
        from(n in Note, where: ^scope, order_by: ^order, limit: ^limit_val)
      else
        from(n in Note, order_by: ^order, limit: ^limit_val)
      end

    base = if starred_only, do: from(n in base, where: n.starred == 1), else: base

    base =
      if type_filter != "all" do
        from(n in base, where: n.parent_type == ^type_filter)
      else
        base
      end

    Repo.all(base)
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
    note = get_note!(note_id)
    new_starred = if note.starred == 1, do: 0, else: 1

    note
    |> Ecto.Changeset.change(starred: new_starred)
    |> Repo.update()
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
      case {Keyword.get(opts, :session_ids), agent_ids} do
        {nil, []} ->
          []

        {nil, _} ->
          from(s in EyeInTheSky.Sessions.Session, where: s.agent_id in ^agent_ids, select: s.id)
          |> Repo.all()
          |> Enum.map(&to_string/1)

        {ids, _} ->
          Enum.map(ids, &to_string/1)
      end

    {extra_where, sql_filter, sql_params} =
      build_note_filters(project_id_str, agent_ids_str, session_ids_str, starred_only)

    PgSearch.search_for(query,
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

  defp build_note_filters(project_id_str, agent_ids_str, session_ids_str, starred_only) do
    has_scope = agent_ids_str != [] or project_id_str != nil or session_ids_str != []
    extra_where = build_extra_where(project_id_str, agent_ids_str, session_ids_str, starred_only, has_scope)
    {sql_filter, sql_params} = build_sql_filter(project_id_str, agent_ids_str, session_ids_str, starred_only, has_scope)
    {extra_where, sql_filter, sql_params}
  end

  defp build_extra_where(project_id_str, agent_ids_str, session_ids_str, starred_only, has_scope) do
    scope_dynamic =
      if has_scope, do: build_scope_dynamic(project_id_str, agent_ids_str, session_ids_str)

    case {scope_dynamic, starred_only} do
      {nil, false} -> nil
      {nil, true} -> dynamic([n], n.starred == 1)
      {scope, false} -> scope
      {scope, true} -> dynamic([n], ^scope and n.starred == 1)
    end
  end

  defp build_sql_filter(project_id_str, agent_ids_str, session_ids_str, starred_only, has_scope) do
    {scope_sql, scope_params} =
      if has_scope,
        do: build_scope_sql(project_id_str, agent_ids_str, session_ids_str),
        else: {"", []}

    if starred_only do
      next_idx = length(scope_params) + 2
      starred_clause = "AND n.starred = $#{next_idx}"
      {scope_sql <> " " <> starred_clause, scope_params ++ [1]}
    else
      {scope_sql, scope_params}
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

  # Builds a raw SQL AND-clause and param list for the FTS query.
  # Params are numbered starting at $2 (since $1 is the FTS search term).
  defp build_scope_sql(project_id_str, agent_ids_str, session_ids_str) do
    {clauses, params, _idx} =
      {[], [], 2}
      |> add_sql_clause(
        project_id_str != nil,
        fn {clauses, params, idx} ->
          clause = "(n.parent_type = 'project' AND n.parent_id = $#{idx})"
          {[clause | clauses], params ++ [project_id_str], idx + 1}
        end
      )
      |> add_sql_clause(
        agent_ids_str != [],
        fn {clauses, params, idx} ->
          placeholders =
            agent_ids_str
            |> Enum.with_index(idx)
            |> Enum.map_join(",", fn {_, i} -> "$#{i}" end)

          clause = "(n.parent_type = 'agent' AND n.parent_id IN (#{placeholders}))"
          {[clause | clauses], params ++ agent_ids_str, idx + length(agent_ids_str)}
        end
      )
      |> add_sql_clause(
        session_ids_str != [],
        fn {clauses, params, idx} ->
          placeholders =
            session_ids_str
            |> Enum.with_index(idx)
            |> Enum.map_join(",", fn {_, i} -> "$#{i}" end)

          clause = "(n.parent_type = 'session' AND n.parent_id IN (#{placeholders}))"
          {[clause | clauses], params ++ session_ids_str, idx + length(session_ids_str)}
        end
      )

    if clauses == [] do
      {"", []}
    else
      {"AND (" <> (clauses |> Enum.reverse() |> Enum.join(" OR ")) <> ")", params}
    end
  end

  defp add_sql_clause(acc, false, _fun), do: acc
  defp add_sql_clause(acc, true, fun), do: fun.(acc)
end

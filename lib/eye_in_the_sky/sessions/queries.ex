defmodule EyeInTheSky.Sessions.Queries do
  @moduledoc """
  Complex query views for sessions: overview rows, filtered listing, and FTS.

  All public functions in this module are also accessible via `EyeInTheSky.Sessions`
  through `defdelegate`. Callers should not depend on this module directly.
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.QueryBuilder
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Scopes.Archivable
  alias EyeInTheSky.Search.PgSearch
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Tasks.WorkflowState

  @current_task_title_fragment """
  (SELECT t.title FROM tasks t JOIN task_sessions ts ON ts.task_id = t.id WHERE ts.session_id = ? AND t.state_id = ? AND t.archived = false ORDER BY t.updated_at DESC LIMIT 1)
  """

  @doc """
  Lists sessions filtered by search query and status filter using PostgreSQL full-text search.
  Excludes archived sessions by default. Pass `include_archived: true` to include archived sessions.

  Options:
  - `:search_query` - String to search across session name, description, project name, agent ID, agent description
  - `:status_filter` - One of: "all", "active", "completed", "stale", "discovered"
  - `:project_id` - Filter by project ID
  - `:agent_id` - Filter by agent ID (integer)
  - `:agent_def_slug` - Filter by agent definition slug (e.g. "eits-cli-expert")
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Number of results to skip (default: 0)
  - `:include_archived` - Include archived sessions (default: false)
  """
  def list_sessions_filtered(opts \\ []) do
    search_query = Keyword.get(opts, :search_query, "")
    status_filter = Keyword.get(opts, :status_filter, "active")
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    project_id = Keyword.get(opts, :project_id, nil)
    agent_id = Keyword.get(opts, :agent_id, nil)

    sort_by = Keyword.get(opts, :sort_by, :last_activity)

    order =
      case sort_by do
        :created -> [desc: :started_at]
        :name -> [asc_nulls_last: :name]
        _ -> [desc_nulls_last: :last_activity_at, desc: :started_at]
      end

    base_query =
      from s in Session,
        join: a in assoc(s, :agent),
        left_join: ad in assoc(a, :agent_definition),
        preload: [agent: {a, agent_definition: ad}],
        order_by: ^order,
        limit: ^limit,
        offset: ^offset

    base_query
    |> Archivable.include_archived(opts)
    |> apply_project_filter(project_id)
    |> apply_agent_filter(agent_id)
    |> apply_agent_def_filter(Keyword.get(opts, :agent_def_slug))
    |> apply_parent_session_filter(Keyword.get(opts, :parent_session_id))
    |> apply_name_filter(Keyword.get(opts, :name_filter))
    |> apply_search_filter(search_query)
    |> apply_status_filter(status_filter)
    |> Repo.all()
  end

  defp apply_project_filter(query, nil), do: query

  defp apply_project_filter(query, project_id) do
    where(query, [s, a], s.project_id == ^project_id or a.project_id == ^project_id)
  end

  defp apply_agent_filter(query, nil), do: query
  defp apply_agent_filter(query, agent_id), do: where(query, [s], s.agent_id == ^agent_id)

  defp apply_agent_def_filter(query, nil), do: query
  defp apply_agent_def_filter(query, slug), do: where(query, [_s, _a, ad], ad.slug == ^slug)

  defp apply_parent_session_filter(query, nil), do: query
  defp apply_parent_session_filter(query, id), do: where(query, [s], s.parent_session_id == ^id)

  defp apply_name_filter(query, nil), do: query
  defp apply_name_filter(query, ""), do: query

  defp apply_name_filter(query, name) do
    where(query, [s], ilike(s.name, ^"%#{name}%"))
  end

  defp apply_status_filter(query, "active") do
    where(query, [s, a], is_nil(s.ended_at) and a.status != "discovered")
  end

  defp apply_status_filter(query, "completed") do
    where(query, [s], not is_nil(s.ended_at))
  end

  defp apply_status_filter(query, "stale") do
    where(query, [s, a], is_nil(s.ended_at) and a.status == "stale")
  end

  defp apply_status_filter(query, "discovered") do
    where(query, [s, a], a.status == "discovered")
  end

  defp apply_status_filter(query, _), do: query

  @doc """
  Returns session overview rows for the sessions table.
  Joins sessions with agents and projects to get complete information.
  Excludes archived sessions by default. Pass `include_archived: true` to include archived sessions.

  Options:
  - `:limit` - Maximum number of results (default: 20)
  - `:include_archived` - Include archived sessions (default: false)
  - `:project_id` - Filter by project ID
  - `:search_query` - PostgreSQL full-text search query across all searchable fields
  """
  def list_session_overview_rows(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    base_overview_query(opts)
    |> order_by([s], desc: s.started_at)
    |> limit(^limit)
    |> QueryBuilder.maybe_offset(opts)
    |> select([s, a, p], %{
      id: s.id,
      uuid: s.uuid,
      name: s.name,
      agent_id: a.id,
      agent_uuid: a.uuid,
      description: s.description,
      project_name: p.name,
      started_at: s.started_at,
      ended_at: s.ended_at,
      status: s.status,
      intent: s.intent,
      entrypoint: s.entrypoint,
      model_provider: s.model_provider,
      model_name: s.model_name,
      model_version: s.model_version,
      last_activity_at: a.last_activity_at,
      current_task_title:
        fragment(
          @current_task_title_fragment,
          s.id,
          ^WorkflowState.in_progress_id()
        )
    })
    |> Repo.all()
  end

  @doc "Fetch a single session in the overview row format (same shape as list_session_overview_rows)."
  def get_session_overview_row(session_id) do
    from(s in Session,
      join: a in assoc(s, :agent),
      left_join: p in EyeInTheSky.Projects.Project,
      on: p.id == a.project_id,
      where: s.id == ^session_id and is_nil(s.archived_at),
      select: %{
        id: s.id,
        uuid: s.uuid,
        name: s.name,
        agent_id: a.id,
        agent_uuid: a.uuid,
        description: s.description,
        project_name: p.name,
        started_at: s.started_at,
        ended_at: s.ended_at,
        status: s.status,
        intent: s.intent,
        entrypoint: s.entrypoint,
        model_provider: s.model_provider,
        model_name: s.model_name,
        model_version: s.model_version,
        last_activity_at: a.last_activity_at,
        current_task_title:
          fragment(
            @current_task_title_fragment,
            s.id,
            ^WorkflowState.in_progress_id()
          )
      }
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @doc """
  Counts sessions for overview (same filters as list_session_overview_rows, without limit/offset).
  """
  def count_session_overview_rows(opts \\ []) do
    base_overview_query(opts)
    |> Repo.aggregate(:count, :id)
  end

  defp base_overview_query(opts) do
    project_id = Keyword.get(opts, :project_id, nil)
    search_query = Keyword.get(opts, :search_query, "")

    query =
      from(s in Session,
        join: a in assoc(s, :agent),
        left_join: p in EyeInTheSky.Projects.Project,
        on: p.id == a.project_id
      )

    query = Archivable.include_archived(query, opts)
    query = if project_id, do: where(query, [s, a], a.project_id == ^project_id), else: query

    apply_search_filter(query, search_query)
  end

  defp apply_search_filter(query, ""), do: query

  defp apply_search_filter(query, search_query) do
    msg_subq = PgSearch.message_fts_session_ids(search_query)
    fts_match = PgSearch.fts_name_description_match(search_query)
    combined = dynamic([s], ^fts_match or s.id in subquery(msg_subq))
    where(query, ^combined)
  end
end

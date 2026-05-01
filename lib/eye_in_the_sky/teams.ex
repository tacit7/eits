defmodule EyeInTheSky.Teams do
  @moduledoc false
  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Agents.Agent
  alias EyeInTheSky.Tasks.Task, as: EitsTask
  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSky.Teams.{Team, TeamMember}
  alias EyeInTheSky.Utils.ToolHelpers

  defp broadcast(event, payload) do
    EyeInTheSky.Events.team_event(event, payload)
  end

  # ── Teams ──────────────────────────────────────────────────

  def list_teams(opts \\ []) do
    query =
      Team
      |> preload(:members)
      |> order_by([t], desc: t.created_at)

    query =
      case Keyword.get(opts, :project_id) do
        nil -> query
        project_id -> where(query, [t], t.project_id == ^project_id)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> where(query, [t], t.status != "archived")
        "all" -> query
        status -> where(query, [t], t.status == ^status)
      end

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        n when n > 0 -> limit(query, ^n)
        _ -> query
      end

    query =
      case Keyword.get(opts, :member_agent_uuid) do
        nil ->
          query

        agent_uuid ->
          query
          |> join(:inner, [t], m in TeamMember, on: m.team_id == t.id)
          |> join(:inner, [_t, m], a in Agent, on: a.id == m.agent_id)
          |> where([_t, _m, a], a.uuid == ^agent_uuid)
          |> distinct(true)
      end

    Repo.all(query)
  end

  def get_team(id) do
    case Repo.get(Team, id) do
      nil -> {:error, :not_found}
      team -> {:ok, team}
    end
  end

  def get_team!(id), do: Repo.get!(Team, id)

  @doc "Preload members with their associated session and agent for a team struct."
  def preload_members(%Team{} = team) do
    Repo.preload(team, members: [session: [:agent]])
  end

  def get_team_by_uuid(uuid) do
    case Repo.get_by(Team, uuid: uuid) do
      nil -> {:error, :not_found}
      team -> {:ok, team}
    end
  end

  def get_team_by_name(name) do
    case Repo.get_by(Team, name: name) do
      nil -> {:error, :not_found}
      team -> {:ok, team}
    end
  end

  def create_team(attrs) do
    %Team{}
    |> Team.changeset(
      Map.put(attrs, :created_at, DateTime.utc_now() |> DateTime.truncate(:second))
    )
    |> Repo.insert()
    |> tap_broadcast(:team_created)
  end

  def update_team(%Team{} = team, attrs) do
    team
    |> Team.update_changeset(attrs)
    |> Repo.update()
    |> tap_broadcast(:team_updated)
  end

  def delete_team(%Team{} = team) do
    team
    |> Team.changeset(%{
      status: "archived",
      archived_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> tap_broadcast(:team_deleted)
  end

  # ── Members ────────────────────────────────────────────────

  def list_members(team_id) do
    members =
      TeamMember
      |> where([m], m.team_id == ^team_id)
      |> preload([:agent, :session])
      |> order_by([m], asc: m.joined_at)
      |> Repo.all()

    attach_claimed_tasks(members)
  end

  defp attach_claimed_tasks([]), do: []

  defp attach_claimed_tasks(members) do
    session_ids = members |> Enum.map(& &1.session_id) |> Enum.reject(&is_nil/1)

    task_by_session =
      if session_ids == [] do
        %{}
      else
        # DISTINCT ON (ts.session_id) with ORDER BY session_id, updated_at DESC
        # picks the most-recent in-progress task per session in one pass,
        # replacing the previous Elixir-side reduce that relied on PG sort order.
        from(t in EitsTask,
          join: ts in "task_sessions", on: ts.task_id == t.id,
          where: ts.session_id in ^session_ids and t.state_id == ^WorkflowState.in_progress_id() and t.archived == false,
          distinct: [asc: ts.session_id],
          order_by: [asc: ts.session_id, desc: t.updated_at],
          select: {ts.session_id, %{id: t.id, title: t.title, state_id: t.state_id}}
        )
        |> Repo.all()
        |> Map.new()
      end

    Enum.map(members, fn m ->
      %{m | claimed_task: Map.get(task_by_session, m.session_id)}
    end)
  end

  def get_member(id) when is_integer(id) do
    case Repo.get(TeamMember, id) do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  def get_member(id) when is_binary(id) do
    case ToolHelpers.parse_int(id) do
      nil -> {:error, :not_found}
      int_id -> get_member(int_id)
    end
  end

  def get_member_by_name(team_id, name) do
    case Repo.get_by(TeamMember, team_id: team_id, name: name) do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  def get_member_by_agent_id(agent_id) do
    result =
      TeamMember
      |> where([m], m.agent_id == ^agent_id)
      |> order_by([m], desc: m.joined_at)
      |> limit(1)
      |> Repo.one()

    case result do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  def join_team(attrs) do
    attrs = Map.put(attrs, :joined_at, DateTime.utc_now() |> DateTime.truncate(:second))

    %TeamMember{}
    |> TeamMember.changeset(attrs)
    |> Repo.insert()
    |> tap_broadcast(:member_joined)
  end

  def update_member_status(%TeamMember{} = member, status) do
    member
    |> TeamMember.changeset(%{
      status: status,
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> tap_broadcast(:member_updated)
  end

  @doc """
  Marks any team member linked to the given session_id as done/failed.
  Called when a session ends to keep member status in sync.
  """
  def mark_member_done_by_session(session_id, status \\ "done")
      when status in ["done", "failed", "idle", "blocked"] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, updated} =
      TeamMember
      |> where([m], m.session_id == ^session_id)
      |> Repo.update_all([set: [status: status, last_activity_at: now]], returning: true)

    Enum.each(updated || [], &broadcast(:member_updated, &1))
    count
  end

  def leave_team(%TeamMember{} = member) do
    Repo.delete(member)
    |> tap_broadcast(:member_left)
  end

  @doc """
  Returns all team members in teams that `session_id` belongs to,
  excluding the calling session itself.

  Used by EITS-CMD `team broadcast` to fan-out a message to co-team members.
  """
  @spec list_broadcast_targets(integer()) :: [TeamMember.t()]
  def list_broadcast_targets(session_id) when is_integer(session_id) do
    TeamMember
    |> join(:inner, [m], other in TeamMember,
      on: other.team_id == m.team_id and other.session_id != ^session_id
    )
    |> where([m, _other], m.session_id == ^session_id)
    |> where([_m, other], not is_nil(other.session_id))
    |> distinct([_m, other], other.session_id)
    |> select([_m, other], other)
    |> Repo.all()
  end

  # ── Helpers ────────────────────────────────────────────────

  defp tap_broadcast({:ok, record}, event) do
    broadcast(event, record)
    {:ok, record}
  end

  defp tap_broadcast({:error, _} = err, _event), do: err
end

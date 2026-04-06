defmodule EyeInTheSky.Teams do
  @moduledoc false
  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
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
        status -> where(query, [t], t.status == ^status)
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
    TeamMember
    |> where([m], m.team_id == ^team_id)
    |> preload([:agent, :session])
    |> order_by([m], asc: m.joined_at)
    |> Repo.all()
  end

  def get_member(id) when is_integer(id) do
    Repo.get(TeamMember, id)
  end

  def get_member(id) when is_binary(id) do
    if int_id = ToolHelpers.parse_int(id), do: get_member(int_id)
  end

  def get_member(team_id, name) do
    Repo.get_by(TeamMember, team_id: team_id, name: name)
  end

  def get_member_by_agent_id(agent_id) do
    TeamMember
    |> where([m], m.agent_id == ^agent_id)
    |> order_by([m], desc: m.joined_at)
    |> limit(1)
    |> Repo.one()
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
      when status in ["done", "failed", "idle"] do
    TeamMember
    |> where([m], m.session_id == ^session_id)
    |> Repo.all()
    |> Enum.each(&update_member_status(&1, status))
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
    |> select([_m, other], other)
    |> Repo.all()
    |> Enum.uniq_by(& &1.session_id)
  end

  # ── Helpers ────────────────────────────────────────────────

  defp tap_broadcast({:ok, record}, event) do
    broadcast(event, record)
    {:ok, record}
  end

  defp tap_broadcast({:error, _} = err, _event), do: err
end

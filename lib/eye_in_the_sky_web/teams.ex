defmodule EyeInTheSkyWeb.Teams do
  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Teams.{Team, TeamMember}

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "teams", {event, payload})
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

  def get_team(id), do: Repo.get(Team, id)

  def get_team!(id), do: Repo.get!(Team, id)

  def get_team_by_uuid(uuid), do: Repo.get_by(Team, uuid: uuid)

  def get_team_by_name(name), do: Repo.get_by(Team, name: name)

  def create_team(attrs) do
    %Team{}
    |> Team.changeset(Map.put(attrs, :created_at, DateTime.utc_now() |> DateTime.truncate(:second)))
    |> Repo.insert()
    |> tap_broadcast(:team_created)
  end

  def delete_team(%Team{} = team) do
    team
    |> Team.changeset(%{status: "archived", archived_at: DateTime.utc_now() |> DateTime.truncate(:second)})
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

  def get_member(team_id, name) do
    Repo.get_by(TeamMember, team_id: team_id, name: name)
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
  def mark_member_done_by_session(session_id, status \\ "done") when status in ["done", "failed", "idle"] do
    case Repo.get_by(TeamMember, session_id: session_id) do
      nil -> :ok
      member -> update_member_status(member, status)
    end
  end

  def leave_team(%TeamMember{} = member) do
    Repo.delete(member)
    |> tap_broadcast(:member_left)
  end

  # ── Helpers ────────────────────────────────────────────────

  defp tap_broadcast({:ok, record}, event) do
    broadcast(event, record)
    {:ok, record}
  end

  defp tap_broadcast({:error, _} = err, _event), do: err
end

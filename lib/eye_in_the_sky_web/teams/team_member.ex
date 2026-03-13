defmodule EyeInTheSkyWeb.Teams.TeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "team_members" do
    field :name, :string
    field :role, :string, default: "member"
    field :status, :string, default: "idle"
    field :joined_at, :utc_datetime
    field :last_activity_at, :utc_datetime

    belongs_to :team, EyeInTheSkyWeb.Teams.Team
    belongs_to :agent, EyeInTheSkyWeb.Agents.Agent
    belongs_to :session, EyeInTheSkyWeb.Sessions.Session
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:team_id, :agent_id, :session_id, :name, :role, :status, :joined_at, :last_activity_at])
    |> validate_required([:team_id, :name])
    |> unique_constraint([:team_id, :name], name: :team_members_team_id_name_index)
  end
end

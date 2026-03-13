defmodule EyeInTheSkyWeb.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "teams" do
    field :uuid, :string
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :created_at, :utc_datetime
    field :archived_at, :utc_datetime

    belongs_to :project, EyeInTheSkyWeb.Projects.Project
    has_many :members, EyeInTheSkyWeb.Teams.TeamMember, foreign_key: :team_id
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:uuid, :name, :description, :status, :project_id, :created_at, :archived_at])
    |> maybe_generate_uuid()
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> unique_constraint(:uuid)
  end

  defp maybe_generate_uuid(changeset) do
    if get_field(changeset, :uuid) do
      changeset
    else
      put_change(changeset, :uuid, Ecto.UUID.generate())
    end
  end
end

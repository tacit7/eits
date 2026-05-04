defmodule EyeInTheSky.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "teams" do
    field :uuid, Ecto.UUID
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :created_at, :utc_datetime
    field :archived_at, :utc_datetime

    belongs_to :project, EyeInTheSky.Projects.Project
    has_many :members, EyeInTheSky.Teams.TeamMember, foreign_key: :team_id
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:uuid, :name, :description, :status, :project_id, :created_at, :archived_at])
    |> maybe_generate_uuid()
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> validate_inclusion(:status, ~w(active archived))
    |> unique_constraint(:name)
    |> unique_constraint(:uuid)
  end

  def update_changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :description])
    |> validate_name_if_present()
    |> unique_constraint(:name)
  end

  defp validate_name_if_present(changeset) do
    if Map.has_key?(changeset.changes, :name) do
      changeset
      |> validate_required([:name])
      |> validate_length(:name, min: 1)
    else
      changeset
    end
  end

  defp maybe_generate_uuid(changeset) do
    if get_field(changeset, :uuid) do
      changeset
    else
      put_change(changeset, :uuid, Ecto.UUID.generate())
    end
  end
end

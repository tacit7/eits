defmodule EyeInTheSky.Workspaces.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "workspaces" do
    field :name, :string
    field :default, :boolean, default: false

    belongs_to :owner_user, EyeInTheSky.Accounts.User, foreign_key: :owner_user_id

    has_many :projects, EyeInTheSky.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :default, :owner_user_id])
    |> validate_required([:name, :owner_user_id])
    |> unique_constraint(:owner_user_id,
      name: :workspaces_owner_user_id_default_unique_index,
      message: "user already has a default workspace"
    )
  end
end

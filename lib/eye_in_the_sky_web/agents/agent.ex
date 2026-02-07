defmodule EyeInTheSkyWeb.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "agents" do
    field :persona_id, :string
    field :source, :string
    field :description, :string
    field :feature_description, :string
    field :status, :string
    field :bookmarked, :boolean, default: false
    field :git_worktree_path, :string
    field :session_id, :string

    belongs_to :project, EyeInTheSkyWeb.Projects.Project, type: :integer

    has_many :sessions, EyeInTheSkyWeb.Sessions.Session, foreign_key: :agent_id
    has_many :tasks, EyeInTheSkyWeb.Tasks.Task, foreign_key: :agent_id

    field :created_at, :string
    field :archived_at, :string
    field :project_name, :string
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :id,
      :persona_id,
      :project_id,
      :source,
      :description,
      :bookmarked,
      :git_worktree_path
    ])
    |> validate_required([:id])
  end
end

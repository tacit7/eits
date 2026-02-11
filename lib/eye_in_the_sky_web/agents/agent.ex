defmodule EyeInTheSkyWeb.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "agents" do
    field :uuid, :string
    field :persona_id, :string
    field :source, :string
    field :description, :string
    field :feature_description, :string
    field :status, :string
    field :bookmarked, :boolean, default: false
    field :git_worktree_path, :string
    field :session_id, :integer

    belongs_to :project, EyeInTheSkyWeb.Projects.Project

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
      :uuid,
      :persona_id,
      :project_id,
      :source,
      :description,
      :bookmarked,
      :git_worktree_path
    ])
    |> validate_required([])
  end
end

defmodule EyeInTheSkyWeb.Agents.Agent do
  @moduledoc """
  DEPRECATED: Use EyeInTheSkyWeb.ChatAgents.ChatAgent instead.

  This is a backward compatibility schema that mirrors ChatAgent.
  The naming has been updated:
  - Agent (old) → ChatAgent (new) - represents chat identities/members
  - Session (old) → Agent (new, future) - represents execution contexts

  This schema will be removed in Phase 2 after all callers are updated.
  For now, it points to the same "agents" table as ChatAgent.
  """

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

    has_many :execution_agents, EyeInTheSkyWeb.ExecutionAgents.ExecutionAgent,
      foreign_key: :agent_id

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

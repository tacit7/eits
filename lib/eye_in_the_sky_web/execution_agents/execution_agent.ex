defmodule EyeInTheSkyWeb.ExecutionAgents.ExecutionAgent do
  @moduledoc """
  Schema for execution agents (autonomous Claude processes doing work).

  Points to the "sessions" database table but represents the conceptual
  ExecutionAgent - an autonomous execution unit, not a chat identity.

  Temporary naming during Step 2 migration. Will be renamed to Agent in Step 8.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "sessions" do
    field :uuid, :string
    field :agent_id, :integer
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :intent, :string
    field :started_at, :string
    field :last_activity_at, :string
    field :ended_at, :string
    field :provider, :string, default: "claude"
    field :model, :string
    field :model_provider, :string
    field :model_name, :string
    field :model_version, :string
    field :archived_at, :string
    field :project_id, :integer
    field :git_worktree_path, :string

    # Renamed from :agent to :chat_agent to avoid collision with future Agents context
    belongs_to :chat_agent, EyeInTheSkyWeb.ChatAgents.ChatAgent,
      define_field: false,
      foreign_key: :agent_id,
      type: :integer

    has_many :logs, EyeInTheSkyWeb.Logs.SessionLog, foreign_key: :session_id
    has_many :commits, EyeInTheSkyWeb.Commits.Commit, foreign_key: :session_id
    has_many :pull_requests, EyeInTheSkyWeb.PullRequests.PullRequest, foreign_key: :session_id

    many_to_many :tasks, EyeInTheSkyWeb.Tasks.Task,
      join_through: "task_sessions",
      join_keys: [session_id: :id, task_id: :id]
  end

  @doc false
  def changeset(execution_agent, attrs) do
    execution_agent
    |> cast(attrs, [
      :uuid,
      :agent_id,
      :name,
      :status,
      :intent,
      :started_at,
      :last_activity_at,
      :ended_at,
      :provider,
      :model,
      :model_provider,
      :model_name,
      :model_version,
      :archived_at,
      :project_id,
      :git_worktree_path
    ])
    |> validate_required([:agent_id, :started_at])
    |> validate_inclusion(:status, ["active", "idle", "completed", "failed", "archived"])
  end

  @doc """
  Changeset for creating an execution agent with model tracking.
  Validates that model_provider and model_name are provided.
  """
  def creation_changeset(execution_agent, attrs) do
    execution_agent
    |> changeset(attrs)
    |> validate_required([:model_provider, :model_name], message: "model information required")
  end
end

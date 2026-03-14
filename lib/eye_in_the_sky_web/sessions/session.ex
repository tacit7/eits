defmodule EyeInTheSkyWeb.Sessions.Session do
  @moduledoc """
  Schema for sessions (autonomous Claude execution contexts).
  Maps to the "sessions" database table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "sessions" do
    field :uuid, :string
    field :agent_id, :integer
    field :name, :string
    field :description, :string
    field :status, :string, default: "idle"
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
    field :parent_agent_id, :integer
    field :parent_session_id, :integer
    field :current_task_title, :string, virtual: true

    belongs_to :agent, EyeInTheSkyWeb.Agents.Agent,
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
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :uuid,
      :agent_id,
      :name,
      :description,
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
      :git_worktree_path,
      :parent_agent_id,
      :parent_session_id
    ])
    |> validate_required([:agent_id, :started_at])
    |> validate_inclusion(:status, [
      "idle",
      "working",
      "compacting",
      "completed",
      "failed",
      "archived"
    ])
  end

  @doc """
  Changeset for creating a session with model tracking.
  Validates that model_provider and model_name are provided.
  """
  def creation_changeset(session, attrs) do
    session
    |> changeset(attrs)
    |> validate_required([:model_provider, :model_name], message: "model information required")
  end
end

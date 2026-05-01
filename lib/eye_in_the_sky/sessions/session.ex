defmodule EyeInTheSky.Sessions.Session do
  @moduledoc """
  Schema for sessions (autonomous Claude execution contexts).
  Maps to the "sessions" database table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "sessions" do
    field :uuid, Ecto.UUID
    field :agent_id, :integer
    field :name, :string
    field :description, :string
    field :status, :string, default: "idle"
    field :intent, :string
    field :started_at, :utc_datetime_usec
    field :last_activity_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :provider, :string, default: "claude"

    # DEPRECATED: :model stores the raw model string received from the API at session
    # creation (e.g. "claude-sonnet-4-6", "haiku"). It predates the structured fields
    # below and is kept only as a fallback for old sessions that have no model_name.
    #
    # Authoritative fields: :model_provider, :model_name, :model_version
    # These are parsed from :model at creation time and are immutable after that.
    #
    # :model is still read in two fallback paths:
    #   1. Sessions.format_model_info/1 — falls back to {provider, model} when
    #      model_name is nil (sessions created before structured fields existed).
    #   2. DmLive — `session.model || "opus"` for the selected-model UI state.
    # checkpoints.ex also copies :model to forked sessions without copying
    # model_provider/model_name, so forks of old sessions may have :model only.
    #
    # Migration plan to remove :model:
    #   1. Backfill: for each session where model_name IS NULL and model IS NOT NULL,
    #      call Sessions.parse_model/1 and write model_provider/model_name.
    #   2. Update DmLive to derive selected_model from Sessions.format_model_info/1
    #      instead of reading session.model directly.
    #   3. Update checkpoints.ex to copy model_provider/model_name instead of model.
    #   4. Remove the {provider, model} fallback branch in Sessions.format_model_info/1.
    #   5. Drop :model from the changeset, schema, and the sessions DB column.
    field :model, :string
    field :model_provider, :string
    field :model_name, :string
    field :model_version, :string
    field :archived_at, :utc_datetime_usec
    field :project_id, :integer
    field :git_worktree_path, :string
    field :parent_agent_id, :integer
    field :parent_session_id, :integer
    field :entrypoint, :string
    field :status_reason, :string
    field :read_only, :boolean, default: false
    # Cached token and cost totals — incremented atomically on each message insert.
    # Avoids full aggregate scans over the messages table for per-session usage display.
    # Source of truth for display; fall back to aggregate query only when nil (pre-migration rows).
    field :total_tokens, :integer, default: 0
    field :total_cost_usd, :float, default: 0.0
    # Virtual field populated by context functions — never set by changesets.
    # Two callers:
    #   1. `Sessions.list_project_sessions_with_agent/2` — populated via
    #      the private `attach_current_task_titles/1` helper, which runs a
    #      separate query joining task_sessions → tasks where state_id = 2
    #      (In Progress) and archived = false, then merges the title into
    #      each session struct.
    #   2. `Sessions.list_session_overview_rows/1` — populated inline via a
    #      correlated SQL subquery (fragment) in the SELECT, applying the
    #      same filters (state_id = 2, archived = false, latest by
    #      updated_at).
    # nil when the session has no in-progress task.
    field :current_task_title, :string, virtual: true

    belongs_to :agent, EyeInTheSky.Agents.Agent,
      define_field: false,
      foreign_key: :agent_id,
      type: :integer

    belongs_to :project, EyeInTheSky.Projects.Project,
      define_field: false,
      foreign_key: :project_id,
      type: :integer

    has_many :logs, EyeInTheSky.Logs.SessionLog, foreign_key: :session_id
    has_many :commits, EyeInTheSky.Commits.Commit, foreign_key: :session_id
    has_many :pull_requests, EyeInTheSky.PullRequests.PullRequest, foreign_key: :session_id

    many_to_many :tasks, EyeInTheSky.Tasks.Task,
      join_through: "task_sessions",
      join_keys: [session_id: :id, task_id: :id]

    timestamps()
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
      :parent_session_id,
      :entrypoint,
      :status_reason,
      :read_only
    ])
    |> validate_required([:agent_id, :started_at])
    |> validate_inclusion(:status, [
      "idle",
      "working",
      "waiting",
      "compacting",
      "completed",
      "failed",
      "archived"
    ])
    |> validate_inclusion(:status_reason, [
      nil,
      "session_ended",
      "sdk_completed",
      "zombie_swept",
      "billing_error",
      "authentication_error",
      "rate_limit_error",
      "watchdog_timeout",
      "retry_exhausted"
    ])
    |> unique_constraint(:uuid, name: :sessions_uuid_index)
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

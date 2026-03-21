defmodule EyeInTheSky.Sessions.Session do
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
    field :archived_at, :string
    field :project_id, :integer
    field :git_worktree_path, :string
    field :parent_agent_id, :integer
    field :parent_session_id, :integer
    field :entrypoint, :string
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

    has_many :logs, EyeInTheSky.Logs.SessionLog, foreign_key: :session_id
    has_many :commits, EyeInTheSky.Commits.Commit, foreign_key: :session_id
    has_many :pull_requests, EyeInTheSky.PullRequests.PullRequest, foreign_key: :session_id

    many_to_many :tasks, EyeInTheSky.Tasks.Task,
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
      :parent_session_id,
      :entrypoint
    ])
    |> validate_required([:agent_id, :started_at])
    |> validate_inclusion(:status, [
      "idle",
      "working",
      "waiting",
      "compacting",
      "stopped",
      "completed",
      "failed",
      "archived"
    ])
    |> validate_iso8601(:started_at)
    |> validate_iso8601(:ended_at)
    |> validate_iso8601(:last_activity_at)
  end

  defp validate_iso8601(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case DateTime.from_iso8601(value) do
        {:ok, _, _} -> []
        {:error, _} -> [{field, "must be a valid ISO8601 timestamp"}]
      end
    end)
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

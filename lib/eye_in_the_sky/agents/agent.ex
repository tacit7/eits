defmodule EyeInTheSky.Agents.Agent do
  @moduledoc """
  Schema for agents (chat agent identities/participants).
  Maps to the "agents" database table.
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

    belongs_to :project, EyeInTheSky.Projects.Project

    has_many :sessions, EyeInTheSky.Sessions.Session, foreign_key: :agent_id

    has_many :tasks, EyeInTheSky.Tasks.Task, foreign_key: :agent_id

    belongs_to :agent_definition, EyeInTheSky.AgentDefinitions.AgentDefinition
    field :definition_checksum_at_spawn, :string

    field :parent_agent_id, :integer
    field :parent_session_id, :integer
    field :created_at, :string
    field :archived_at, :string
    # Denormalized from the projects table. Populated at read time by
    # Agents.populate_project_name/1 (which reads agent.project.name after
    # preloading the association). It is NOT written back to the DB — the
    # column exists for legacy/external-read convenience but is never persisted
    # via changeset. Always call populate_project_name/1 after any query that
    # needs this value.
    field :project_name, :string
    field :last_activity_at, :string
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :uuid,
      :persona_id,
      :project_id,
      :project_name,
      :source,
      :description,
      :status,
      :bookmarked,
      :git_worktree_path,
      :parent_agent_id,
      :parent_session_id,
      :last_activity_at,
      :agent_definition_id,
      :definition_checksum_at_spawn
    ])
    |> maybe_generate_uuid()
    |> validate_required([])
  end

  defp maybe_generate_uuid(changeset) do
    if Ecto.Changeset.get_field(changeset, :uuid) do
      changeset
    else
      Ecto.Changeset.put_change(changeset, :uuid, Ecto.UUID.generate())
    end
  end
end

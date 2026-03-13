defmodule EyeInTheSkyWeb.Agents.Agent do
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

    belongs_to :project, EyeInTheSkyWeb.Projects.Project

    has_many :sessions, EyeInTheSkyWeb.Sessions.Session, foreign_key: :agent_id

    has_many :tasks, EyeInTheSkyWeb.Tasks.Task, foreign_key: :agent_id

    field :parent_agent_id, :integer
    field :parent_session_id, :integer
    field :created_at, :string
    field :archived_at, :string
    field :project_name, :string
    field :last_activity_at, :naive_datetime
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
      :git_worktree_path,
      :parent_agent_id,
      :parent_session_id
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

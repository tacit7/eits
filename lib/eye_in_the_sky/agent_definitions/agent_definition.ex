defmodule EyeInTheSky.AgentDefinitions.AgentDefinition do
  @moduledoc """
  Schema for agent definition files discovered on the filesystem.

  Catalogs `.md` agent files from:
  - Global: `~/.claude/agents/*.md`
  - Project: `<project_path>/.claude/agents/*.md`

  These are *definitions*, not runtime agents. Runtime agents (in the `agents` table)
  may link back to a definition via `agent_definition_id`.

  ## Path semantics

  - `scope: "global"` → `path` is absolute (e.g. `/Users/foo/.claude/agents/code-auditor.md`)
  - `scope: "project"` → `path` is relative to project root (e.g. `.claude/agents/code-auditor.md`)
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_definitions" do
    field :slug, :string
    field :display_name, :string
    field :scope, :string
    field :path, :string
    field :description, :string
    field :model, :string
    field :tools, {:array, :string}, default: []
    field :checksum, :string
    field :last_synced_at, :utc_datetime_usec
    field :missing_at, :utc_datetime_usec

    belongs_to :project, EyeInTheSky.Projects.Project

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:slug, :scope, :path]
  @optional_fields [
    :display_name,
    :project_id,
    :description,
    :model,
    :tools,
    :checksum,
    :last_synced_at,
    :missing_at
  ]

  def changeset(definition, attrs) do
    definition
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:scope, ["global", "project"])
    |> validate_project_scope()
  end

  defp validate_project_scope(changeset) do
    scope = get_field(changeset, :scope)
    project_id = get_field(changeset, :project_id)

    cond do
      scope == "project" and is_nil(project_id) ->
        add_error(changeset, :project_id, "is required when scope is 'project'")

      scope == "global" and not is_nil(project_id) ->
        add_error(changeset, :project_id, "must be nil when scope is 'global'")

      true ->
        changeset
    end
  end
end

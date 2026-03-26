defmodule EyeInTheSkyWeb.Assistants.Assistant do
  @moduledoc """
  Schema for reusable assistant definitions.
  An assistant wraps a prompt with executable configuration (model, effort, tool policy, scope).
  Maps to the "assistants" database table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @valid_trigger_types ~w(manual task_dispatch schedule api)
  @valid_efforts ~w(low medium high)

  schema "assistants" do
    field :name, :string
    field :model, :string
    field :reasoning_effort, :string
    field :tool_policy, :map, default: %{}
    field :default_trigger_type, :string, default: "manual"
    field :team_id, :integer
    field :active, :boolean, default: true

    belongs_to :prompt, EyeInTheSkyWeb.Prompts.Prompt, foreign_key: :prompt_id
    belongs_to :project, EyeInTheSkyWeb.Projects.Project, foreign_key: :project_id

    field :inserted_at, :naive_datetime
    field :updated_at, :naive_datetime
  end

  @doc false
  def changeset(assistant, attrs) do
    assistant
    |> cast(attrs, [
      :name,
      :prompt_id,
      :model,
      :reasoning_effort,
      :tool_policy,
      :default_trigger_type,
      :project_id,
      :team_id,
      :active
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:default_trigger_type, @valid_trigger_types,
      message: "must be one of: #{Enum.join(@valid_trigger_types, ", ")}"
    )
    |> validate_inclusion(:reasoning_effort, @valid_efforts ++ [nil],
      message: "must be one of: #{Enum.join(@valid_efforts, ", ")}"
    )
    |> foreign_key_constraint(:prompt_id)
    |> foreign_key_constraint(:project_id)
  end
end

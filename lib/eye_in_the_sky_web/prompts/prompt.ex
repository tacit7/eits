defmodule EyeInTheSkyWeb.Prompts.Prompt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "subagent_prompts" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :prompt_text, :string
    field :project_id, :string
    field :active, :boolean, default: true
    field :version, :integer, default: 1
    field :tags, :string
    field :created_by, :string
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime
  end

  @doc false
  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, [
      :id,
      :name,
      :slug,
      :description,
      :prompt_text,
      :project_id,
      :active,
      :version,
      :tags,
      :created_by
    ])
    |> validate_required([:name, :slug, :prompt_text])
    |> validate_format(:slug, ~r/^[a-z][a-z0-9-]*$/,
      message: "must be kebab-case (lowercase letters, numbers, and hyphens only)"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:slug, min: 1, max: 100)
    |> unique_constraint(:slug, name: :idx_subagent_prompts_slug_global)
    |> unique_constraint([:slug, :project_id], name: :idx_subagent_prompts_slug_project)
    |> maybe_generate_id()
  end

  defp maybe_generate_id(changeset) do
    case get_field(changeset, :id) do
      nil -> put_change(changeset, :id, Ecto.UUID.generate())
      _ -> changeset
    end
  end
end

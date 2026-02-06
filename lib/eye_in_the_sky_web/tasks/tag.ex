defmodule EyeInTheSkyWeb.Tasks.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :color, :string

    many_to_many :tasks, EyeInTheSkyWeb.Tasks.Task,
      join_through: "task_tags",
      join_keys: [tag_id: :id, task_id: :id]
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end

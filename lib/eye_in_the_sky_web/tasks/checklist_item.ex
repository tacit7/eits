defmodule EyeInTheSkyWeb.Tasks.ChecklistItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "checklist_items" do
    field :title, :string
    field :completed, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :task, EyeInTheSkyWeb.Tasks.Task

    timestamps()
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:title, :completed, :position, :task_id])
    |> validate_required([:title, :task_id])
  end
end

defmodule EyeInTheSkyWeb.Tasks.WorkflowState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "workflow_states" do
    field :name, :string
    field :position, :integer
    field :color, :string

    has_many :tasks, EyeInTheSkyWeb.Tasks.Task, foreign_key: :state_id

    field :updated_at, :utc_datetime
  end

  @doc false
  def changeset(workflow_state, attrs) do
    workflow_state
    |> cast(attrs, [:name, :position, :color])
    |> validate_required([:name, :position])
    |> unique_constraint(:name)
    |> unique_constraint(:position)
  end
end

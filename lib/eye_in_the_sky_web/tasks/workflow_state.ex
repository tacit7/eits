defmodule EyeInTheSkyWeb.Tasks.WorkflowState do
  use Ecto.Schema
  import Ecto.Changeset

  # Workflow state IDs matching the workflow_states table
  @todo_id 1
  @in_progress_id 2
  @in_review_id 4
  @done_id 3

  def todo_id, do: @todo_id
  def in_progress_id, do: @in_progress_id
  def in_review_id, do: @in_review_id
  def done_id, do: @done_id

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

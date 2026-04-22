defmodule EyeInTheSky.Tasks.WorkflowState do
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

    has_many :tasks, EyeInTheSky.Tasks.Task, foreign_key: :state_id

    field :updated_at, :utc_datetime
  end

  @aliases %{
    "done" => "Done",
    "start" => "In Progress",
    "progress" => "In Progress",
    "in-review" => "In Review",
    "review" => "In Review",
    "todo" => "To Do"
  }

  @doc """
  Resolves a string alias to a canonical workflow state name.

  Returns `{:ok, state_name}` on match, `{:error, :no_alias}` for nil/numeric
  input, and `{:error, :invalid_alias}` for unrecognized non-numeric strings.
  """
  @spec resolve_alias(String.t() | nil) ::
          {:ok, String.t()} | {:error, :no_alias | :invalid_alias}
  def resolve_alias(nil), do: {:error, :no_alias}

  def resolve_alias(input) when is_binary(input) do
    case Integer.parse(input) do
      {_, ""} ->
        {:error, :no_alias}

      _ ->
        case Map.get(@aliases, String.downcase(input)) do
          nil -> {:error, :invalid_alias}
          name -> {:ok, name}
        end
    end
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

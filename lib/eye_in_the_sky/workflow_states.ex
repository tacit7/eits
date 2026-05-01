defmodule EyeInTheSky.WorkflowStates do
  @moduledoc """
  Context for managing workflow states (kanban columns).
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Tasks.WorkflowState

  @doc """
  Returns the list of workflow states ordered by position.
  """
  def list_workflow_states do
    WorkflowState
    |> order_by([ws], asc: ws.position)
    |> Repo.all()
  end

  @doc """
  Reorder workflow states by a list of IDs in desired order.

  A single UPDATE … FROM unnest() replaces the previous per-row loop, reducing
  N round-trips to 1. The position unique constraint is DEFERRABLE INITIALLY
  DEFERRED, so uniqueness is checked at commit — no temp negative positions needed.
  """
  def reorder_workflow_states(ordered_ids) when is_list(ordered_ids) do
    {ids, positions} =
      ordered_ids
      |> Enum.with_index(1)
      |> Enum.map(fn {id, idx} -> {id, idx} end)
      |> Enum.unzip()

    sql = """
    UPDATE workflow_states SET position = data.position
    FROM (SELECT unnest($1::int[]) AS id, unnest($2::int[]) AS position) AS data
    WHERE workflow_states.id = data.id
    """

    Repo.transaction(fn -> Repo.query!(sql, [ids, positions]) end)
  end

  @doc """
  Gets a single workflow state.

  Raises `Ecto.NoResultsError` if the WorkflowState does not exist.
  """
  def get_workflow_state!(id) do
    Repo.get!(WorkflowState, id)
  end

  @doc """
  Gets a workflow state by name. Returns {:ok, state} | {:error, :not_found}.
  """
  def get_workflow_state_by_name(name) do
    case Repo.get_by(WorkflowState, name: name) do
      nil -> {:error, :not_found}
      state -> {:ok, state}
    end
  end
end

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
  The position unique constraint is DEFERRABLE INITIALLY DEFERRED, so uniqueness
  is checked at commit rather than per-statement — no temp negative positions needed.
  """
  def reorder_workflow_states(ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {id, idx} ->
        from(ws in WorkflowState, where: ws.id == ^id)
        |> Repo.update_all(set: [position: idx])
      end)
    end)
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

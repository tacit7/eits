defmodule EyeInTheSky.ChecklistItems do
  @moduledoc """
  Context for managing task checklist items.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Tasks.ChecklistItem

  @doc """
  Lists checklist items for a task, ordered by position.
  """
  def list_checklist_items(task_id) do
    ChecklistItem
    |> where([c], c.task_id == ^task_id)
    |> order_by([c], asc: c.position, asc: c.id)
    |> Repo.all()
  end

  @doc """
  Creates a checklist item for a task.
  """
  def create_checklist_item(attrs) do
    %ChecklistItem{}
    |> ChecklistItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Toggles a checklist item's completed state.
  """
  def toggle_checklist_item(id) do
    case Repo.get(ChecklistItem, id) do
      nil ->
        {:error, :not_found}

      item ->
        item
        |> ChecklistItem.changeset(%{completed: !item.completed})
        |> Repo.update()
    end
  end

  @doc """
  Deletes a checklist item.
  """
  def delete_checklist_item(id) do
    case Repo.get(ChecklistItem, id) do
      nil -> {:error, :not_found}
      item -> Repo.delete(item)
    end
  end
end

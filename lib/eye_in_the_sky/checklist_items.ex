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
    |> limit(200)
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

  Uses a single UPDATE ... SET completed = NOT completed RETURNING * to avoid
  the SELECT-then-UPDATE two-query pattern. Returns {:ok, item} or {:error, :not_found}.
  """
  def toggle_checklist_item(id) do
    case Repo.query(
           "UPDATE checklist_items SET completed = NOT completed WHERE id = $1 RETURNING *",
           [id]
         ) do
      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:ok, %{rows: [row], columns: cols}} ->
        item = Repo.load(ChecklistItem, Enum.zip(cols, row))
        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a checklist item.

  Uses DELETE ... RETURNING id to avoid the SELECT-then-DELETE two-query pattern.
  Returns :ok or {:error, :not_found}.
  """
  def delete_checklist_item(id) do
    case Repo.query(
           "DELETE FROM checklist_items WHERE id = $1 RETURNING id",
           [id]
         ) do
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

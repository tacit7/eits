defmodule EyeInTheSky.TaskTags do
  @moduledoc """
  Context for managing tags and task-tag associations.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Tasks.Tag

  @doc """
  Returns the list of tags.
  """
  def list_tags do
    Repo.all(Tag)
  end

  @doc """
  Gets a single tag.

  Raises `Ecto.NoResultsError` if the Tag does not exist.
  """
  def get_tag!(id) do
    Repo.get!(Tag, id)
  end

  @doc """
  Updates a tag's attributes (e.g., color).
  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets or creates a tag by name.
  """
  def get_or_create_tag(name) do
    case Repo.get_by(Tag, name: name) do
      nil ->
        %Tag{}
        |> Tag.changeset(%{name: name})
        |> Repo.insert()

      tag ->
        {:ok, tag}
    end
  end

  @doc """
  Replaces all tags on a task with the given list of tag names.
  Deletes existing tag associations and inserts new ones.
  No-op if tag_names is empty (leaves existing tags unchanged).
  """
  def replace_task_tags(_task_id, []), do: :ok

  def replace_task_tags(task_id, tag_names) when is_list(tag_names) do
    tag_rows =
      Enum.flat_map(tag_names, fn tag_name ->
        case get_or_create_tag(tag_name) do
          {:ok, tag} -> [%{task_id: task_id, tag_id: tag.id}]
          _ -> []
        end
      end)

    Repo.delete_all(from(t in "task_tags", where: t.task_id == ^task_id))
    Repo.insert_all("task_tags", tag_rows, on_conflict: :nothing)
  end

  @doc """
  Links a tag to a task via the task_tags join table.
  """
  def link_tag_to_task(task_id, tag_id)
      when is_integer(task_id) and is_integer(tag_id) do
    {count, _} =
      Repo.insert_all("task_tags", [%{task_id: task_id, tag_id: tag_id}], on_conflict: :nothing)

    {:ok, count}
  end
end

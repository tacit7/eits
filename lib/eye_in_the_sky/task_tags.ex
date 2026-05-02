defmodule EyeInTheSky.TaskTags do
  @moduledoc """
  Context for managing tags and task-tag associations.
  """

  import Ecto.Query
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
    # H6 fix: one upsert replaces N get_or_create_tag SELECTs (1-2 queries × N).
    # ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name is a no-op write that
    # forces the row into the RETURNING clause even when the tag already exists.
    # This means no second SELECT is needed even in race conditions.
    #
    # Wrapped in a transaction so the delete + insert are atomic: a concurrent
    # reader cannot see the task with an empty tag list between the two statements.
    tag_inserts = Enum.map(tag_names, &%{name: &1})

    Repo.transaction(fn ->
      {_count, tags} =
        Repo.insert_all(Tag, tag_inserts,
          on_conflict: {:replace, [:name]},
          conflict_target: :name,
          returning: [:id]
        )

      task_tag_rows = Enum.map(tags, &%{task_id: task_id, tag_id: &1.id})

      Repo.delete_all(from(t in "task_tags", where: t.task_id == ^task_id))
      Repo.insert_all("task_tags", task_tag_rows, on_conflict: :nothing)
    end)

    :ok
  end

  @doc """
  Links a tag to a task via the task_tags join table.

  Returns `:ok` on success (including when the association already exists),
  `{:error, :not_found}` when either the task_id or tag_id does not exist
  (FK violation), or `{:error, reason}` for other DB errors.
  """
  @spec link_tag_to_task(integer(), integer()) ::
          :ok | {:error, :not_found} | {:error, term()}
  def link_tag_to_task(task_id, tag_id)
      when is_integer(task_id) and is_integer(tag_id) do
    case Repo.query(
           "INSERT INTO task_tags (task_id, tag_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
           [task_id, tag_id]
         ) do
      {:ok, _} -> :ok
      {:error, %{postgres: %{code: :foreign_key_violation}}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end

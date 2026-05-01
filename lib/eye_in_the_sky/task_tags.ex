defmodule EyeInTheSky.TaskTags do
  @moduledoc """
  Context for managing tags and task-tag associations.
  """

  import Ecto.Query
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Tasks.Tag

  @doc """
  Returns the list of tags, optionally filtered by name search (case-insensitive substring).

  Options:
  - `:search` - case-insensitive substring filter on tag name
  - `:limit` - cap results (default: 500)
  """
  def list_tags(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    query =
      case Keyword.get(opts, :search) do
        search when is_binary(search) and search != "" ->
          from(t in Tag, where: ilike(t.name, ^"%#{search}%"))

        _ ->
          Tag
      end

    query
    |> order_by([t], asc: t.name)
    |> limit(^limit)
    |> Repo.all()
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

  Uses an atomic upsert to avoid the TOCTOU race of SELECT-then-INSERT.
  ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name is a no-op write that
  forces the row into RETURNING even when the tag already exists, so no second
  SELECT is needed in concurrent scenarios.
  """
  def get_or_create_tag(name) do
    case Repo.insert_all(Tag, [%{name: name}],
           on_conflict: {:replace, [:name]},
           conflict_target: :name,
           returning: true
         ) do
      {_n, [tag]} -> {:ok, tag}
      _ -> {:error, :insert_failed}
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
    tag_inserts = Enum.map(tag_names, &%{name: &1})

    {_count, tags} =
      Repo.insert_all(Tag, tag_inserts,
        on_conflict: {:replace, [:name]},
        conflict_target: :name,
        returning: [:id]
      )

    task_tag_rows = Enum.map(tags, &%{task_id: task_id, tag_id: &1.id})

    Repo.delete_all(from(t in "task_tags", where: t.task_id == ^task_id))
    Repo.insert_all("task_tags", task_tag_rows, on_conflict: :nothing)
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

defmodule EyeInTheSky.Bookmarks do
  @moduledoc """
  The Bookmarks context for managing bookmarks.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Bookmarks.Bookmark

  @doc """
  Returns the list of bookmarks with optional filters.

  ## Options

    * `:bookmark_type` - Filter by type (file, note, agent, session, task, url)
    * `:category` - Filter by category
    * `:project_id` - Filter by project
    * `:agent_id` - Filter by agent
    * `:limit` - Maximum number of results (default: 100)
    * `:order_by` - Order by field (default: priority DESC, inserted_at DESC)

  """
  def list_bookmarks(opts \\ []) do
    query = from(b in Bookmark)

    query
    |> maybe_filter_by_type(opts[:bookmark_type])
    |> maybe_filter_by_category(opts[:category])
    |> maybe_filter_by_project(opts[:project_id])
    |> maybe_filter_by_agent(opts[:agent_id])
    |> apply_ordering(opts[:order_by])
    |> maybe_limit(opts[:limit] || 100)
    |> Repo.all()
  end

  @doc """
  Gets a single bookmark.

  Raises `Ecto.NoResultsError` if the Bookmark does not exist.
  """
  def get_bookmark!(id), do: Repo.get!(Bookmark, id)

  @doc """
  Creates a bookmark.
  """
  def create_bookmark(attrs \\ %{}) do
    %Bookmark{}
    |> Bookmark.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a bookmark.
  """
  def update_bookmark(%Bookmark{} = bookmark, attrs) do
    bookmark
    |> Bookmark.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bookmark.
  """
  def delete_bookmark(%Bookmark{} = bookmark) do
    Repo.delete(bookmark)
  end

  @doc """
  Checks if an entity is bookmarked.

  ## Examples

      iex> check_if_bookmarked("file", "/path/to/file.go")
      true

      iex> check_if_bookmarked("agent", "abc-123")
      false

  """
  def check_if_bookmarked(bookmark_type, identifier) do
    case bookmark_type do
      "file" ->
        from(b in Bookmark, where: b.bookmark_type == "file" and b.file_path == ^identifier)
        |> Repo.exists?()

      type when type in ["note", "agent", "session", "task"] ->
        from(b in Bookmark, where: b.bookmark_type == ^type and b.bookmark_id == ^identifier)
        |> Repo.exists?()

      _ ->
        false
    end
  end

  @doc """
  Gets a bookmark by type and identifier.
  """
  def get_bookmark_by(bookmark_type, identifier) do
    case bookmark_type do
      "file" ->
        from(b in Bookmark, where: b.bookmark_type == "file" and b.file_path == ^identifier)
        |> Repo.one()

      type when type in ["note", "agent", "session", "task"] ->
        from(b in Bookmark, where: b.bookmark_type == ^type and b.bookmark_id == ^identifier)
        |> Repo.one()

      _ ->
        nil
    end
  end

  @doc """
  Records that a bookmark was accessed (updates accessed_at).
  """
  def touch_bookmark(%Bookmark{} = bookmark) do
    bookmark
    |> Ecto.Changeset.change(accessed_at: DateTime.utc_now())
    |> Repo.update()
  end

  # Private helpers

  defp maybe_filter_by_type(query, nil), do: query

  defp maybe_filter_by_type(query, type) do
    from b in query, where: b.bookmark_type == ^type
  end

  defp maybe_filter_by_category(query, nil), do: query

  defp maybe_filter_by_category(query, category) do
    from b in query, where: b.category == ^category
  end

  defp maybe_filter_by_project(query, nil), do: query

  defp maybe_filter_by_project(query, project_id) do
    from b in query, where: b.project_id == ^project_id
  end

  defp maybe_filter_by_agent(query, nil), do: query

  defp maybe_filter_by_agent(query, agent_id) do
    from b in query, where: b.agent_id == ^agent_id
  end

  defp apply_ordering(query, nil) do
    from b in query, order_by: [desc: b.priority, desc: b.inserted_at]
  end

  defp apply_ordering(query, "priority") do
    from b in query, order_by: [desc: b.priority]
  end

  defp apply_ordering(query, "created_at") do
    from b in query, order_by: [desc: b.inserted_at]
  end

  defp apply_ordering(query, "accessed_at") do
    from b in query, order_by: [desc: b.accessed_at]
  end

  defp apply_ordering(query, "position") do
    from b in query, order_by: [asc: b.position]
  end

  defp apply_ordering(query, _), do: apply_ordering(query, nil)

  defp maybe_limit(query, limit) do
    from b in query, limit: ^limit
  end
end

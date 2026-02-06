defmodule EyeInTheSkyWeb.Scopes.Archivable do
  @moduledoc """
  Query scope for filtering archived records.

  Provides consistent archive filtering across contexts that support archiving.
  """

  import Ecto.Query, warn: false

  @doc """
  Excludes archived records from query.

  Filters out records where `archived_at` is not nil.

  ## Examples

      iex> Session |> exclude_archived() |> Repo.all()
      [%Session{archived_at: nil}, ...]
  """
  def exclude_archived(query) do
    where(query, [q], is_nil(q.archived_at))
  end

  @doc """
  Conditionally includes or excludes archived records based on opts.

  If `include_archived: true` is passed in opts, returns query unchanged.
  Otherwise, filters out archived records.

  ## Examples

      iex> Session |> include_archived(include_archived: true) |> Repo.all()
      [%Session{}, %Session{archived_at: ~N[...]}, ...]

      iex> Session |> include_archived([]) |> Repo.all()
      [%Session{archived_at: nil}, ...]
  """
  def include_archived(query, opts) when is_list(opts) do
    if Keyword.get(opts, :include_archived, false) do
      query
    else
      exclude_archived(query)
    end
  end
end

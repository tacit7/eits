defmodule EyeInTheSky.Commits do
  @moduledoc """
  The Commits context for managing git commits.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Commits.Commit
  alias EyeInTheSky.QueryHelpers
  alias EyeInTheSky.Repo

  @doc """
  Returns the list of commits.
  """
  def list_commits(opts \\ []) do
    Commit
    |> EyeInTheSky.QueryBuilder.maybe_limit(opts)
    |> Repo.all()
  end

  @doc """
  Returns the list of commits for a specific agent.
  """
  def list_commits_for_agent(agent_id) do
    Commit
    |> where([c], c.agent_id == ^agent_id)
    |> order_by([c], desc: c.created_at)
    |> Repo.all()
  end

  @doc """
  Returns recent commits for a session with a limit.
  """
  def list_recent_commits(session_id, limit \\ 10) do
    Commit
    |> where([c], c.session_id == ^session_id)
    |> order_by([c], desc: c.created_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns commits for a specific session.
  """
  def list_commits_for_session(session_id, opts \\ []) do
    QueryHelpers.for_session_direct(Commit, session_id,
      order_by: [desc: :created_at],
      limit: Keyword.get(opts, :limit)
    )
  end

  @doc """
  Counts commits for a specific session.
  """
  def count_commits_for_session(session_id) do
    QueryHelpers.count_for_session(Commit, session_id)
  end

  @doc """
  Returns recent commits for multiple sessions in a single query.
  """
  def list_commits_for_sessions(session_ids, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Commit
    |> where([c], c.session_id in ^session_ids)
    |> order_by([c], desc: c.created_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single commit.

  Raises `Ecto.NoResultsError` if the Commit does not exist.
  """
  def get_commit!(id) do
    Repo.get!(Commit, id)
  end

  @doc """
  Gets a commit by hash.
  """
  def get_commit_by_hash(hash) do
    case Repo.get_by(Commit, commit_hash: hash) do
      nil -> {:error, :not_found}
      commit -> {:ok, commit}
    end
  end

  @doc """
  Creates a commit.
  """
  def create_commit(attrs \\ %{}) do
    %Commit{}
    |> Commit.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :commit_hash)
  end

  @doc """
  Updates a commit.
  """
  def update_commit(%Commit{} = commit, attrs) do
    commit
    |> Commit.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a commit.
  """
  def delete_commit(%Commit{} = commit) do
    Repo.delete(commit)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking commit changes.
  """
  def change_commit(%Commit{} = commit, attrs \\ %{}) do
    Commit.changeset(commit, attrs)
  end
end

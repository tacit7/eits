defmodule EyeInTheSky.PullRequests do
  import Ecto.Query
  alias EyeInTheSky.PullRequests.PullRequest
  alias EyeInTheSky.Repo

  @doc """
  List all pull requests for a session.
  """
  def list_prs_for_session(session_id) do
    Repo.all(
      from pr in PullRequest, where: pr.session_id == ^session_id, order_by: [desc: pr.created_at]
    )
  end

  @doc """
  Get a single pull request by ID.
  """
  def get_pr!(id) do
    Repo.get!(PullRequest, id)
  end

  @doc """
  Create a new pull request.
  """
  def create_pr(attrs \\ %{}) do
    %PullRequest{}
    |> PullRequest.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a pull request.
  """
  def update_pr(%PullRequest{} = pr, attrs) do
    pr
    |> PullRequest.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a pull request.
  """
  def delete_pr(%PullRequest{} = pr) do
    Repo.delete(pr)
  end

  @doc """
  Return an `%Ecto.Changeset{}` for tracking pull request changes.
  """
  def change_pr(%PullRequest{} = pr, attrs \\ %{}) do
    PullRequest.changeset(pr, attrs)
  end
end

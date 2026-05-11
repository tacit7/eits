defmodule EyeInTheSky.Github.PullRequestHandler do
  require Logger

  alias EyeInTheSky.Repo
  alias EyeInTheSky.PullRequests.PullRequest
  alias EyeInTheSky.Events

  def handle(%{event_type: "pull_request" <> _, github_pr_id: nil}), do: :ok

  def handle(ctx) do
    attrs = %{
      github_pr_id: ctx.github_pr_id,
      pr_number: ctx.pr_number,
      repository_full_name: ctx.repository_full_name,
      author_login: ctx.sender_login,
      head_branch: ctx.head_branch,
      base_branch: ctx.base_branch,
      draft: ctx.draft?,
      merged: ctx.merged?,
      state: derive_state(ctx),
      last_synced_at: DateTime.utc_now()
    }

    result =
      case Repo.get_by(PullRequest, github_pr_id: ctx.github_pr_id) do
        nil ->
          %PullRequest{}
          |> PullRequest.github_sync_changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> PullRequest.github_sync_changeset(attrs)
          |> Repo.update()
      end

    case result do
      {:ok, pr} ->
        Events.pull_request_updated(pr)

      {:error, changeset} ->
        Logger.error("PullRequestHandler upsert failed: #{inspect(changeset)}")
    end
  end

  defp derive_state(%{event_type: "pull_request.closed"}), do: "closed"
  defp derive_state(_), do: "open"
end

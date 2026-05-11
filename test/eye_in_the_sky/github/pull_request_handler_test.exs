defmodule EyeInTheSky.Github.PullRequestHandlerTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.PullRequestHandler
  alias EyeInTheSky.Repo
  alias EyeInTheSky.PullRequests.PullRequest

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %EyeInTheSky.Github.EventContext{
        delivery_id: "d1",
        event_type: "pull_request.opened",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        github_pr_id: 100,
        pr_number: 1,
        head_branch: "feature/x",
        base_branch: "main",
        labels: [],
        draft?: false,
        merged?: false
      },
      overrides
    )
  end

  test "inserts a pull_request row on opened" do
    PullRequestHandler.handle(ctx())
    pr = Repo.get_by(PullRequest, github_pr_id: 100)
    assert pr != nil
    assert pr.repository_full_name == "tacit7/eits"
    assert pr.pr_number == 1
  end

  test "does not create duplicate for same github_pr_id" do
    PullRequestHandler.handle(ctx())
    PullRequestHandler.handle(ctx(%{event_type: "pull_request.synchronize"}))
    count = Repo.aggregate(PullRequest, :count, :id)
    assert count == 1
  end

  test "same pr_number in different repos does not collide" do
    PullRequestHandler.handle(ctx())
    PullRequestHandler.handle(ctx(%{github_pr_id: 200, repository_full_name: "other/repo"}))
    assert Repo.aggregate(PullRequest, :count, :id) == 2
  end

  test "marks merged=true and state=closed on closed+merged" do
    PullRequestHandler.handle(ctx())
    PullRequestHandler.handle(ctx(%{event_type: "pull_request.closed", merged?: true}))
    pr = Repo.get_by(PullRequest, github_pr_id: 100)
    assert pr.merged == true
    assert pr.state == "closed"
  end
end

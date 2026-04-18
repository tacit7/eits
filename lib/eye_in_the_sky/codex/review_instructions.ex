defmodule EyeInTheSky.Codex.ReviewInstructions do
  @moduledoc """
  Builds Codex agent instructions for reviewing a pull request.
  """

  @doc """
  Builds the review instructions string for a given PR context map.
  """
  def build(%{
        number: pr_number,
        title: pr_title,
        body: pr_body,
        url: pr_url,
        head_branch: head_branch,
        repo: repo
      }) do
    {owner, repo_name} = split_repo(repo)

    """
    You are a code reviewer. Review PR ##{pr_number} in the #{repo} repo.

    PR Title: #{pr_title}
    PR URL: #{pr_url}
    Branch: #{head_branch}

    PR Description:
    #{pr_body}

    Steps:
    1. Run: tea pr view #{pr_number} --login codex --repo #{owner}/#{repo_name}
    2. Check the diff: git fetch gitea && git diff gitea/main...gitea/#{head_branch}
    3. Review the changes for: correctness, security, code quality, missing tests, breaking changes.
    4. Post a concise review comment:
       tea comment #{pr_number} --login codex --repo #{owner}/#{repo_name} "your review here"
       - Start with: LGTM / NEEDS CHANGES / BLOCKED
       - List specific issues with file:line references if applicable
       - Keep it actionable and direct

    Focus on real issues. Skip praise.
    """
  end

  defp split_repo(repo) do
    case String.split(repo, "/", parts: 2) do
      [owner, name] -> {owner, name}
      _ -> {"claude", repo}
    end
  end
end

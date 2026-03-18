defmodule EyeInTheSkyWeb.Agents.InstructionBuilder do
  @moduledoc """
  Builds instruction strings for agent sessions.

  Combines user-supplied instructions with workflow suffixes
  (e.g. git worktree push + PR creation steps).
  """

  @doc """
  Builds the initial instruction string for an agent session.

  ## Options
    * `:instructions` - Explicit instruction string. Falls back to `:description` then `"Agent session"`.
    * `:description` - Human-readable description used as fallback base text.
    * `:worktree` - Worktree name. When set, appends a git + PR workflow suffix.

  ## Examples

      iex> build([instructions: "Do the thing"])
      "Do the thing"

      iex> build([description: "Fix bug"])
      "Fix bug"

      iex> build([])
      "Agent session"

      iex> build([instructions: "Do the thing", worktree: "my-feature"])
      "Do the thing\\n\\n---\\nWhen your work is complete:..."
  """
  def build(opts) do
    description = opts[:description] || "Agent session"

    case opts[:worktree] do
      nil ->
        opts[:instructions] || description

      worktree ->
        base = opts[:instructions] || description
        branch = "worktree-#{worktree}"

        base <>
          """


          ---
          When your work is complete:
          1. Commit all changes with a clear message describing what was done.
          2. Push your branch: git push gitea #{branch}
          3. Create a pull request: tea pr create --login claude --repo eits-web --base main --head #{branch} --title "<your task summary>" --description "<what you did and why>"
          4. Call i-end-session to mark your session complete.
          """
    end
  end
end

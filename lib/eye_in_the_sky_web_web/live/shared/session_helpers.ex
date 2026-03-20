defmodule EyeInTheSkyWebWeb.Live.Shared.SessionHelpers do
  @moduledoc """
  Shared helpers for LiveViews that interact with Claude sessions.

  Covers model/effort/thinking option building and project path resolution.
  """

  @doc """
  Builds the options list for `AgentManager.continue_session/3` from
  the current model, effort level, thinking, and budget selections.
  """
  @spec continue_session_opts(String.t(), String.t() | nil, boolean(), float() | nil) ::
          keyword()
  def continue_session_opts(model, effort_level, thinking_enabled, max_budget_usd) do
    opts = [model: model]

    opts =
      if is_binary(effort_level) and effort_level != "" do
        opts ++ [effort_level: effort_level]
      else
        opts
      end

    opts =
      if thinking_enabled do
        budget =
          case model do
            "opus" -> 16000
            _ -> 10000
          end

        opts ++ [thinking_budget: budget]
      else
        opts
      end

    if max_budget_usd do
      opts ++ [max_budget_usd: max_budget_usd]
    else
      opts
    end
  end

  @doc """
  Resolves the filesystem path for a session's project.

  Priority: session worktree > agent worktree > agent project path.
  Returns `{:error, :no_project_path}` when none is configured.
  """
  @spec resolve_project_path(map(), map()) :: {:ok, String.t()} | {:error, :no_project_path}
  def resolve_project_path(session, agent) do
    cond do
      session.git_worktree_path ->
        {:ok, session.git_worktree_path}

      agent.git_worktree_path ->
        {:ok, agent.git_worktree_path}

      agent.project && agent.project.path ->
        {:ok, agent.project.path}

      true ->
        {:error, :no_project_path}
    end
  end
end

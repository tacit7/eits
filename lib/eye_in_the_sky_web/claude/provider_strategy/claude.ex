defmodule EyeInTheSkyWeb.Claude.ProviderStrategy.Claude do
  @moduledoc """
  ProviderStrategy implementation for the Claude Code CLI provider.
  """

  @behaviour EyeInTheSkyWeb.Claude.ProviderStrategy

  alias EyeInTheSkyWeb.Claude.{AgentWorker, SDK}

  require Logger

  @impl true
  def start(%AgentWorker{} = state, job) do
    context = job.context
    prompt = job.message

    optional_opts =
      [
        effort_level: context[:effort_level],
        thinking_budget: context[:thinking_budget],
        max_budget_usd: context[:max_budget_usd]
      ]
      |> Keyword.filter(fn {k, v} -> v != nil && (k != :effort_level || v != "") end)

    opts =
      [
        to: self(),
        model: context[:model],
        session_id: state.provider_conversation_id,
        project_path: state.project_path,
        skip_permissions: true,
        use_script: true,
        eits_session_id: state.provider_conversation_id,
        eits_agent_id: state.agent_id,
        eits_workflow: context[:eits_workflow] || "1",
        worktree: state.worktree,
        agent: context[:agent]
      ] ++ optional_opts

    Logger.info("Starting new Claude session #{state.provider_conversation_id}")
    SDK.start(prompt, opts)
  end

  @impl true
  def resume(%AgentWorker{} = state, job) do
    context = job.context
    prompt = job.message

    optional_opts =
      [
        effort_level: context[:effort_level],
        thinking_budget: context[:thinking_budget],
        max_budget_usd: context[:max_budget_usd]
      ]
      |> Keyword.filter(fn {k, v} -> v != nil && (k != :effort_level || v != "") end)

    opts =
      [
        to: self(),
        model: context[:model],
        session_id: state.provider_conversation_id,
        project_path: state.project_path,
        skip_permissions: true,
        use_script: true,
        eits_session_id: state.provider_conversation_id,
        eits_agent_id: state.agent_id,
        eits_workflow: context[:eits_workflow] || "1",
        worktree: state.worktree,
        agent: context[:agent]
      ] ++ optional_opts

    Logger.info("Resuming Claude session #{state.provider_conversation_id}")
    SDK.resume(state.provider_conversation_id, prompt, opts)
  end

  @impl true
  def cancel(ref) do
    SDK.cancel(ref)
  end
end

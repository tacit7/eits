defmodule EyeInTheSky.Claude.ProviderStrategy.Claude do
  @moduledoc """
  ProviderStrategy implementation for the Claude Code CLI provider.
  """

  @behaviour EyeInTheSky.Claude.ProviderStrategy

  alias EyeInTheSky.Claude.SDK

  require Logger

  @impl true
  def start(state, job) do
    opts = build_opts(state, job.context)
    Logger.info("Starting new Claude session #{state.provider_conversation_id}")
    SDK.start(job.message, opts)
  end

  @impl true
  def resume(state, job) do
    opts = build_opts(state, job.context)
    Logger.info("Resuming Claude session #{state.provider_conversation_id}")
    SDK.resume(state.provider_conversation_id, job.message, opts)
  end

  @impl true
  def cancel(ref) do
    SDK.cancel(ref)
  end

  @doc """
  Build the EITS init prompt appended to new Claude sdk-cli sessions.

  Injects session-specific EITS context and EITS-CMD directive instructions.
  Accepts any struct with the fields: eits_session_uuid, session_id, agent_id, project_id.
  """
  @spec eits_init_prompt(map()) :: String.t()
  def eits_init_prompt(state) do
    """
    EITS context:
    - EITS_SESSION_UUID=#{state.eits_session_uuid}
    - EITS_SESSION_ID=#{state.session_id}
    - EITS_AGENT_UUID=#{state.agent_id}
    - EITS_PROJECT_ID=#{state.project_id}

    You are running as sdk-cli. Use EITS-CMD directives (intercepted in-process, no HTTP required):

      EITS-CMD: task begin <title>
      EITS-CMD: task annotate <id> <body>
      EITS-CMD: task done <id>
      EITS-CMD: note <body>
      EITS-CMD: commit <hash>
      EITS-CMD: dm --to #{state.eits_session_uuid} --message <text>

    Write EITS-CMD lines anywhere in your output. They are stripped before display.
    You MUST claim a task before editing files:
      EITS-CMD: task begin <title of your work>
    """
  end

  defp build_opts(state, context) do
    optional_opts =
      [
        effort_level: context[:effort_level],
        thinking_budget: context[:thinking_budget],
        max_budget_usd: context[:max_budget_usd]
      ]
      |> Keyword.filter(fn {k, v} -> v != nil && (k != :effort_level || v != "") end)

    eits_workflow = context[:eits_workflow] || "1"

    base_opts = [
      to: self(),
      model: context[:model],
      session_id: state.provider_conversation_id,
      project_path: state.project_path,
      skip_permissions: true,
      use_script: true,
      eits_session_id: state.provider_conversation_id,
      eits_agent_id: state.agent_id,
      eits_workflow: eits_workflow,
      worktree: state.worktree,
      agent: context[:agent]
    ]

    base_opts =
      if eits_workflow != "0" do
        Keyword.put(base_opts, :append_system_prompt, eits_init_prompt(state))
      else
        base_opts
      end

    base_opts ++ optional_opts
  end
end

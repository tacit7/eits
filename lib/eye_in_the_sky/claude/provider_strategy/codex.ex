defmodule EyeInTheSky.Claude.ProviderStrategy.Codex do
  @moduledoc """
  ProviderStrategy implementation for the OpenAI Codex CLI provider.
  """

  @behaviour EyeInTheSky.Claude.ProviderStrategy

  alias EyeInTheSky.Codex

  require Logger

  @impl true
  def start(state, job) do
    context = job.context
    prompt = job.message

    opts = build_opts(state, context)

    full_prompt =
      if (context[:eits_workflow] || "1") != "0" do
        Codex.SDK.eits_init_prompt(state) <> "\n\n---\n\n" <> prompt
      else
        prompt
      end

    Logger.info("Starting new Codex session #{state.provider_conversation_id}")
    Codex.SDK.start(full_prompt, opts)
  end

  @impl true
  def resume(state, job) do
    context = job.context
    prompt = job.message

    opts = build_opts(state, context)

    Logger.info("Resuming Codex session #{state.provider_conversation_id}")
    Codex.SDK.resume(state.provider_conversation_id, prompt, opts)
  end

  @impl true
  def cancel(ref) do
    Codex.SDK.cancel(ref)
  end

  defp build_opts(state, context) do
    [
      to: self(),
      model: context[:model],
      session_id: state.provider_conversation_id,
      project_path: state.project_path,
      full_auto: true,
      bypass_sandbox: context[:bypass_sandbox] || false,
      eits_session_uuid: state.eits_session_uuid,
      eits_session_id: state.session_id,
      eits_agent_uuid: state.agent_id,
      eits_agent_id: state.agent_id,
      eits_project_id: state.project_id,
      eits_model: context[:model],
      eits_url: System.get_env("EITS_URL", "http://localhost:5001/api/v1")
    ]
  end
end

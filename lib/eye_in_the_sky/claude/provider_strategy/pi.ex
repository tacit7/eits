defmodule EyeInTheSky.Claude.ProviderStrategy.Pi do
  @moduledoc """
  ProviderStrategy implementation for the Pi harness provider.
  Phase 1: bypass approval mode only (allowedTools: ["*"]).
  """

  @behaviour EyeInTheSky.Claude.ProviderStrategy

  alias EyeInTheSky.Claude.ProviderStrategy
  alias EyeInTheSky.Pi

  require Logger

  @impl true
  def format_content(block), do: ProviderStrategy.format_content_default(block)

  @impl true
  def start(state, job) do
    opts = build_opts(state, job.context)
    warn_content_blocks(job.content_blocks)
    Logger.info("Starting new Pi session #{state.provider_conversation_id}")
    Pi.SDK.start(job.message, opts)
  end

  @impl true
  def resume(state, job) do
    opts = build_opts(state, job.context)
    warn_content_blocks(job.content_blocks)
    Logger.info("Resuming Pi session #{state.provider_conversation_id}")
    Pi.SDK.resume(state.provider_conversation_id, job.message, opts)
  end

  @impl true
  def cancel(ref), do: Pi.SDK.cancel(ref)

  @doc false
  def build_opts(state, context) do
    [
      to: self(),
      model: context[:model],
      session_id: state.provider_conversation_id,
      project_path: state.project_path,
      allowed_tools: ["*"],
      custom_instructions: eits_custom_instructions(state, context),
      turn_id: Base.encode16(:crypto.strong_rand_bytes(6), case: :lower),
      eits_session_uuid: state.eits_session_uuid,
      eits_session_id: state.session_id,
      eits_agent_uuid: state.agent_id,
      eits_agent_id: state.agent_id,
      eits_project_id: state.project_id,
      eits_channel_id: context[:channel_id],
      eits_model: context[:model],
      eits_url: System.get_env("EITS_URL", "http://localhost:5001/api/v1")
    ]
  end

  defp eits_custom_instructions(state, context) do
    if (context[:eits_workflow] || "1") != "0" do
      pi_eits_init_prompt(state)
    else
      nil
    end
  end

  defp warn_content_blocks([]), do: :ok
  defp warn_content_blocks(nil), do: :ok

  defp warn_content_blocks(blocks) when is_list(blocks) do
    Logger.warning("[Pi] Stripping #{length(blocks)} content block(s): Pi Phase 1 is text-only")
  end

  @eits_cli_reference """
    eits tasks begin --title "<title>"
    eits tasks annotate <id> --body "..."
    eits tasks update <id> --state 4
    eits dm --to <session_uuid> --message "<text>"
    eits commits create --hash <hash>
  """

  defp pi_eits_init_prompt(state) do
    """
    EITS context:
    - EITS_SESSION_UUID=#{state.eits_session_uuid}
    - EITS_SESSION_ID=#{state.session_id}
    - EITS_AGENT_ID=#{state.agent_id}
    - EITS_PROJECT_ID=#{state.project_id}

    Use the eits CLI script for all EITS operations:

    #{@eits_cli_reference}
    To spawn a child agent, always pass --provider pi:
      eits agents spawn --provider pi --instructions "<text>" [--model <model>]

    You MUST claim a task before editing files:
      eits tasks begin --title "<title of your work>"

    Now proceed with the task:
    """
  end
end

defmodule EyeInTheSky.Claude.ProviderStrategy.Claude do
  @moduledoc """
  ProviderStrategy implementation for the Claude Code CLI provider.
  """

  @behaviour EyeInTheSky.Claude.ProviderStrategy

  alias EyeInTheSky.Claude.{ContentBlock, SDK}

  require Logger

  @impl true
  def format_content(%ContentBlock.Text{text: text}) do
    %{"type" => "text", "text" => text}
  end

  @impl true
  def format_content(%ContentBlock.Image{data: data, mime_type: mime_type}) do
    %{
      "type" => "image",
      "source" => %{"type" => "base64", "media_type" => mime_type, "data" => data}
    }
  end

  @impl true
  def format_content(%ContentBlock.Document{source: source}) do
    %{
      "type" => "document",
      "source" => %{"type" => "base64", "media_type" => source.media_type, "data" => source.data}
    }
  end

  @doc """
  Builds a full content array from a text string and a list of ContentBlock structs.
  """
  @spec format_message(String.t(), [ContentBlock.t()]) :: [map()]
  def format_message(text, content_blocks) do
    text_block = %{"type" => "text", "text" => text}
    image_blocks = Enum.map(content_blocks, &format_content/1)
    [text_block | image_blocks]
  end

  @impl true
  def start(state, job) do
    opts = build_opts(state, job.context)
    opts = maybe_add_content_blocks(opts, job.content_blocks)
    message = maybe_append_metadata(job.message, job.context[:dm_metadata])
    Logger.info("Starting new Claude session #{state.provider_conversation_id}")
    SDK.start(message, opts)
  end

  @impl true
  def resume(state, job) do
    opts = build_opts(state, job.context)
    opts = maybe_add_content_blocks(opts, job.content_blocks)
    message = maybe_append_metadata(job.message, job.context[:dm_metadata])
    Logger.info("Resuming Claude session #{state.provider_conversation_id}")
    SDK.resume(state.provider_conversation_id, message, opts)
  end

  @impl true
  def cancel(ref) do
    SDK.cancel(ref)
  end

  @doc """
  Build the EITS init prompt appended to new Claude sdk-cli sessions.

  Injects session-specific EITS context and eits CLI workflow instructions.
  Accepts any struct with the fields: eits_session_uuid, session_id, agent_id, project_id.
  """
  @spec eits_init_prompt(map(), keyword()) :: String.t()
  def eits_init_prompt(state, opts \\ []) do
    channel_line =
      case opts[:channel_id] do
        nil -> ""
        id -> "\n- EITS_CHANNEL_ID=#{id}"
      end

    """
    EITS context:
    - EITS_SESSION_UUID=#{state.eits_session_uuid}
    - EITS_SESSION_ID=#{state.session_id}
    - EITS_AGENT_ID=#{state.agent_id}
    - EITS_PROJECT_ID=#{state.project_id}#{channel_line}

    Use the eits CLI script for all EITS operations:

      eits tasks begin --title "<title>"
      eits tasks annotate <id> --body "..."
      eits tasks update <id> --state 4
      eits dm --to <session_uuid> --message "<text>"
      eits commits create --hash <hash>

    You MUST claim a task before editing files:
      eits tasks begin --title "<title of your work>"
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
      eits_session_id: state.session_id,
      eits_agent_id: state.agent_id,
      eits_channel_id: context[:channel_id],
      eits_workflow: eits_workflow,
      worktree: state.worktree,
      agent: context[:agent]
    ]

    base_opts =
      if eits_workflow != "0" do
        Keyword.put(base_opts, :append_system_prompt, eits_init_prompt(state, channel_id: context[:channel_id]))
      else
        base_opts
      end

    extra = context[:extra_cli_opts] || []
    base_opts ++ optional_opts ++ extra
  end

  defp maybe_add_content_blocks(opts, []), do: opts

  defp maybe_add_content_blocks(opts, content_blocks) when is_list(content_blocks) do
    formatted = Enum.map(content_blocks, &format_content/1)
    Keyword.put(opts, :content_blocks, formatted)
  end

  # If dm_metadata contains custom fields (beyond auto-populated ones), append them to the message.
  # Auto-populated fields (sender_name, from_session_uuid, to_session_uuid, response_required)
  # are already in the message body via DMDelivery, so we only include additional custom fields
  # to give the agent machine-readable structured context.
  defp maybe_append_metadata(message, nil), do: message
  defp maybe_append_metadata(message, %{} = metadata) do
    # Filter out auto-populated fields; keep only custom fields
    auto_fields = ~w(sender_name from_session_uuid to_session_uuid response_required)a
    custom_fields = Map.drop(metadata, auto_fields)

    if map_size(custom_fields) > 0 do
      # Append metadata as JSON for structured context
      metadata_json = Jason.encode!(custom_fields)
      message <> "\n\n## Metadata\n```json\n" <> metadata_json <> "\n```"
    else
      message
    end
  end
  defp maybe_append_metadata(message, _), do: message
end

defmodule EyeInTheSky.Claude.ProviderStrategy.Gemini do
  @moduledoc """
  ProviderStrategy implementation for the Gemini CLI SDK provider.
  """

  @behaviour EyeInTheSky.Claude.ProviderStrategy

  alias EyeInTheSky.Claude.ContentBlock
  alias EyeInTheSky.Claude.ProviderStrategy.Claude

  require Logger

  @stream_handler Application.compile_env(
                    :eye_in_the_sky,
                    :gemini_stream_handler,
                    EyeInTheSky.Gemini.StreamHandler
                  )

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

  @impl true
  def start(state, job) do
    opts = build_opts(state, job.context)
    Logger.info("Starting new Gemini session #{state.provider_conversation_id}")
    @stream_handler.start(job.message, opts, self())
  end

  @impl true
  def resume(state, job) do
    opts = build_opts(state, job.context, state.provider_conversation_id)
    Logger.info("Resuming Gemini session #{state.provider_conversation_id}")
    @stream_handler.resume(state.provider_conversation_id, job.message, opts, self())
  end

  @impl true
  def cancel(ref) do
    @stream_handler.cancel(ref)
  end

  defp build_opts(state, context, resume_id \\ nil) do
    %GeminiCliSdk.Options{
      cwd: state.project_path,
      model: context[:model] || "gemini-2.5-flash",
      resume: resume_id,
      yolo: true,
      system_prompt: Claude.eits_init_prompt(state),
      env: %{
        "EITS_SESSION_UUID" => state.eits_session_uuid,
        "EITS_SESSION_ID" => to_string(state.session_id),
        "EITS_AGENT_UUID" => state.agent_id,
        "EITS_PROJECT_ID" => to_string(state.project_id)
      },
      allowed_tools: context[:allowed_tools] || [],
      timeout_ms: 300_000
    }
  end
end

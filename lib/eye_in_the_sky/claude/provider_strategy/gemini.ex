defmodule EyeInTheSky.Claude.ProviderStrategy.Gemini do
  @moduledoc """
  ProviderStrategy implementation for the Gemini CLI SDK provider.
  """

  @behaviour EyeInTheSky.Claude.ProviderStrategy

  alias EyeInTheSky.Claude.ContentBlock
  alias EyeInTheSky.Claude.ProviderStrategy.Claude

  require Logger

  defp stream_handler do
    Application.get_env(:eye_in_the_sky, :gemini_stream_handler, EyeInTheSky.Gemini.StreamHandler)
  end

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
    stream_handler().start(job.message, opts, self())
  end

  @impl true
  def resume(state, job) do
    opts = build_opts(state, job.context, state.provider_conversation_id)
    Logger.info("Resuming Gemini session #{state.provider_conversation_id}")
    stream_handler().resume(state.provider_conversation_id, job.message, opts, self())
  end

  @impl true
  def cancel(ref) do
    stream_handler().cancel(ref)
  end

  defp build_opts(state, context, resume_id \\ nil) do
    %GeminiCliSdk.Options{
      cwd: state.project_path,
      model: context[:model] || "gemini-2.5-flash",
      resume: resume_id,
      yolo: true,
      system_prompt: maybe_system_prompt_path(state, context),
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

  # The gemini_cli_sdk's `system_prompt` field maps to GEMINI_SYSTEM_MD, which
  # the Gemini CLI interprets as a *path* to a markdown file — not inline
  # content. Two consequences:
  #
  #   1. We must write to a file and pass the path, otherwise the CLI fails
  #      with "missing system prompt file '<the prompt text>'".
  #   2. Unlike Claude's `--append-system-prompt`, GEMINI_SYSTEM_MD *replaces*
  #      the CLI's default system prompt. So we only inject when EITS workflow
  #      is explicitly requested (eits_workflow="1"). When the user opts out
  #      via `eits_workflow="0"`, return nil so the SDK skips the env var
  #      entirely and Gemini boots with its default prompt.
  defp maybe_system_prompt_path(state, context) do
    case context[:eits_workflow] do
      "0" -> nil
      _ -> write_system_prompt_file(state)
    end
  end

  defp write_system_prompt_file(state) do
    content = Claude.eits_init_prompt(state)
    dir = Path.join(System.tmp_dir!(), "eits-gemini")
    File.mkdir_p!(dir)
    path = Path.join(dir, "system-#{state.session_id}.md")
    File.write!(path, content)
    path
  end
end

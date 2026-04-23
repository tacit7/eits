defmodule EyeInTheSky.Claude.ProviderStrategy do
  @moduledoc """
  Behaviour defining the interface for provider-specific SDK operations.

  Each provider (Claude, Codex) implements start/2, resume/3, and cancel/1
  to handle SDK lifecycle in a uniform way from AgentWorker's perspective.

  All implementations return `{:ok, sdk_ref, handler_pid}` or `{:error, reason}`.
  """

  alias EyeInTheSky.Claude.ContentBlock

  @type sdk_result :: {:ok, reference(), pid()} | {:error, term()}

  @doc "Start a new provider session."
  @callback start(state :: map(), job :: struct()) :: sdk_result()

  @doc "Resume an existing provider session."
  @callback resume(state :: map(), job :: struct()) :: sdk_result()

  @doc "Cancel a running provider session by SDK ref."
  @callback cancel(ref :: reference()) :: :ok | {:error, term()}

  @doc "Format a ContentBlock into a provider-specific map representation."
  @callback format_content(term()) :: map()

  @doc "Normalize a raw provider response map into a canonical format."
  @callback normalize_response(map()) :: map()

  @optional_callbacks format_content: 1, normalize_response: 1

  @doc "Default format_content implementation for ContentBlock structs."
  @spec format_content_default(ContentBlock.t()) :: map()
  def format_content_default(%ContentBlock.Text{text: t}),
    do: %{"type" => "text", "text" => t}

  def format_content_default(%ContentBlock.Image{data: d, mime_type: m}),
    do: %{"type" => "image", "data" => d, "mime_type" => m}

  def format_content_default(%ContentBlock.Document{source: s}),
    do: %{"type" => "document", "source" => s}

  @doc "Return the strategy module for a given provider string."
  @spec for_provider(String.t()) :: module()
  def for_provider("codex"), do: EyeInTheSky.Claude.ProviderStrategy.Codex
  def for_provider("gemini"), do: EyeInTheSky.Claude.ProviderStrategy.Gemini
  def for_provider(_), do: EyeInTheSky.Claude.ProviderStrategy.Claude
end

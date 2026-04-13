defmodule EyeInTheSky.Claude.ModelCapabilities do
  @moduledoc """
  Model capability registry for multimodal content filtering.

  Maps model identifiers to their supported input modalities so that
  unsupported content blocks can be silently stripped before reaching
  the provider. This follows the Open Claw pattern of graceful
  degradation: no errors thrown, unsupported content is just dropped.

  ## Supported modalities

  - `:text` — all models
  - `:image` — vision-capable models
  - `:document` — native PDF support (Anthropic only)
  """

  alias EyeInTheSky.Claude.ContentBlock

  @type modality :: :text | :image | :document

  # Claude models — all support image, opus/sonnet support document (native PDF)
  @claude_vision_models ~w(opus sonnet haiku claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-5)
  @claude_document_models ~w(opus sonnet claude-opus-4-6 claude-sonnet-4-6)

  # Codex/OpenAI models — vision support varies
  @codex_vision_models ~w(gpt-4-turbo gpt-4o gpt-5 gpt-5.3 gpt-5.3-codex)

  @doc """
  Returns the set of supported input modalities for a given model string.
  Defaults to [:text, :image] for unknown models (safe assumption for modern LLMs).
  """
  @spec modalities(String.t() | nil) :: [modality()]
  def modalities(nil), do: [:text, :image]

  def modalities(model) when is_binary(model) do
    model_lower = String.downcase(model)

    cond do
      matches_any?(model_lower, @claude_document_models) ->
        [:text, :image, :document]

      matches_any?(model_lower, @claude_vision_models) ->
        [:text, :image]

      matches_any?(model_lower, @codex_vision_models) ->
        [:text, :image]

      # Legacy or text-only models
      String.contains?(model_lower, "codex") and not String.contains?(model_lower, "gpt") ->
        [:text]

      # Default: assume modern model with vision
      true ->
        [:text, :image]
    end
  end

  @doc """
  Returns true if the model supports the given modality.
  """
  @spec supports?(String.t() | nil, modality()) :: boolean()
  def supports?(model, modality), do: modality in modalities(model)

  @doc """
  Filters a list of content blocks to only those supported by the model.

  Silently drops unsupported blocks. Text blocks are never dropped.
  """
  @spec filter_blocks([ContentBlock.t()], String.t() | nil) :: [ContentBlock.t()]
  def filter_blocks(blocks, model) when is_list(blocks) do
    supported = modalities(model)

    Enum.filter(blocks, fn block ->
      cond do
        ContentBlock.text?(block) -> :text in supported
        ContentBlock.image?(block) -> :image in supported
        ContentBlock.document?(block) -> :document in supported
        true -> false
      end
    end)
  end

  defp matches_any?(model_lower, patterns) do
    Enum.any?(patterns, fn pattern ->
      String.contains?(model_lower, String.downcase(pattern))
    end)
  end
end

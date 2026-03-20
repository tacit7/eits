defmodule EyeInTheSkyWeb.Claude.ProviderStrategy do
  @moduledoc """
  Behaviour defining the interface for provider-specific SDK operations.

  Each provider (Claude, Codex) implements start/2, resume/3, and cancel/1
  to handle SDK lifecycle in a uniform way from AgentWorker's perspective.

  All implementations return `{:ok, sdk_ref, handler_pid}` or `{:error, reason}`.
  """

  alias EyeInTheSkyWeb.Claude.AgentWorker

  @type sdk_result :: {:ok, reference(), pid()} | {:error, term()}

  @doc "Start a new provider session."
  @callback start(state :: %AgentWorker{}, job :: struct()) :: sdk_result()

  @doc "Resume an existing provider session."
  @callback resume(state :: %AgentWorker{}, job :: struct()) :: sdk_result()

  @doc "Cancel a running provider session by SDK ref."
  @callback cancel(ref :: reference()) :: :ok | {:error, term()}

  @doc "Return the strategy module for a given provider string."
  @spec for_provider(String.t()) :: module()
  def for_provider("codex"), do: EyeInTheSkyWeb.Claude.ProviderStrategy.Codex
  def for_provider(_), do: EyeInTheSkyWeb.Claude.ProviderStrategy.Claude
end

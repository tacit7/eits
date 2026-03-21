defmodule EyeInTheSky.Sessions.ModelInfo do
  @moduledoc """
  Model information parsing and formatting utilities for sessions.

  Handles extraction of model provider, name, and version from various formats,
  and provides formatted output for display purposes.
  """

  alias EyeInTheSky.Sessions.Session

  @doc """
  Extracts and validates model information from a nested model object.

  Expects model info in format:
    {
      "provider": "anthropic",
      "name": "claude-3-5-sonnet",
      "version": "20241022"  # optional
    }

  Returns {:ok, model_attrs} or {:error, reason}.
  """
  def extract_model_info(model_data) when is_map(model_data) do
    with provider when is_binary(provider) <- model_data["provider"] || model_data[:provider],
         name when is_binary(name) <- model_data["name"] || model_data[:name] do
      version = model_data["version"] || model_data[:version]

      {:ok,
       %{
         model_provider: provider,
         model_name: name,
         model_version: version
       }}
    else
      nil -> {:error, "Missing required model fields: provider and name"}
      _ -> {:error, "Invalid model data structure"}
    end
  end

  def extract_model_info(nil) do
    {:error, "Model information required"}
  end

  def extract_model_info(_) do
    {:error, "Model must be a map"}
  end

  @doc """
  Gets model information for a session as a formatted string.

  Returns "provider/name (version)" or "provider/name" if version not set.
  """
  def format_model_info(%{model_name: name} = session) when is_binary(name) and name != "" do
    version = Map.get(session, :model_version)

    name
    |> with_version(version)
    |> strip_claude_prefix()
  end

  def format_model_info(%Session{} = session) do
    session
    |> resolve_model_string()
    |> strip_claude_prefix()
  end

  def format_model_info(_), do: "unknown"

  # Private helpers

  defp with_version(name, version) when is_binary(version) and version != "",
    do: "#{name} (#{version})"

  defp with_version(name, _), do: name

  defp resolve_model_string(%Session{model_name: name, model_version: version})
       when is_binary(name) and name != "" and is_binary(version) and version != "",
       do: "#{name} (#{version})"

  defp resolve_model_string(%Session{model_name: name})
       when is_binary(name) and name != "",
       do: name

  defp resolve_model_string(%Session{model: m})
       when is_binary(m) and m != "",
       do: m

  defp resolve_model_string(%Session{provider: p})
       when is_binary(p) and p != "",
       do: p

  defp resolve_model_string(_), do: "unknown"

  defp strip_claude_prefix(str) do
    str
    |> String.replace(~r/^claude-/, "")
    |> String.replace(~r/^claude\//, "")
  end
end

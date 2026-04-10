defmodule EyeInTheSky.Agents.SpawnValidator do
  @moduledoc """
  Validates parameters for spawning a new agent via the REST API.
  """

  alias EyeInTheSky.{Agents, Sessions}
  alias EyeInTheSky.Agents.ModelConfig

  @doc """
  Validates and normalizes spawn parameters.

  Returns `{:ok, normalized_params}` on success, or
  `{:error, code, message}` on failure.
  """
  def validate(params) do
    provider = params["provider"] || "claude"
    model = params["model"] || if(provider == "codex", do: "gpt-5.3-codex", else: "haiku")

    with {:ok, instructions} <- validate_instructions(params["instructions"]),
         {:ok, _} <- validate_provider_model(provider, model),
         {:ok, parent_agent_id} <- coerce_parent_id(params["parent_agent_id"], "parent_agent_id"),
         {:ok, parent_session_id} <-
           coerce_parent_id(params["parent_session_id"], "parent_session_id"),
         {:ok, _} <- validate_parent_agent(parent_agent_id),
         {:ok, _} <- validate_parent_session(parent_session_id) do
      {:ok,
       Map.merge(params, %{
         "instructions" => instructions,
         "provider" => provider,
         "model" => model,
         "parent_agent_id" => parent_agent_id,
         "parent_session_id" => parent_session_id
       })}
    end
  end

  defp coerce_parent_id(nil, _field), do: {:ok, nil}
  defp coerce_parent_id("", _field), do: {:ok, nil}
  defp coerce_parent_id(val, _field) when is_integer(val), do: {:ok, val}

  defp coerce_parent_id(val, field) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "invalid_parameter", "#{field} must be an integer"}
    end
  end

  defp coerce_parent_id(_val, field),
    do: {:error, "invalid_parameter", "#{field} must be an integer"}

  defp validate_instructions(nil),
    do: {:error, "missing_required", "instructions is required"}

  defp validate_instructions(val) when is_binary(val) do
    trimmed = String.trim(val)

    cond do
      trimmed == "" ->
        {:error, "missing_required", "instructions is required"}

      String.length(trimmed) > 32_000 ->
        {:error, "instructions_too_long", "instructions exceeds 32000 character limit"}

      true ->
        {:ok, trimmed}
    end
  end

  defp validate_provider_model(provider, model) do
    combos = ModelConfig.valid_model_combos()

    case Map.get(combos, provider) do
      nil ->
        valid_providers = combos |> Map.keys() |> Enum.join(", ")

        {:error, "invalid_provider",
         "invalid provider '#{provider}'; must be one of: #{valid_providers}"}

      valid_models ->
        if model in valid_models do
          {:ok, {provider, model}}
        else
          {:error, "invalid_model",
           "invalid model '#{model}' for provider '#{provider}'; valid models: #{Enum.join(valid_models, ", ")}"}
        end
    end
  end

  defp validate_parent_agent(nil), do: {:ok, nil}

  defp validate_parent_agent(id) do
    case Agents.get_agent(id) do
      {:ok, _} -> {:ok, id}
      {:error, :not_found} -> {:error, "parent_not_found", "parent_agent_id #{id} does not exist"}
    end
  end

  defp validate_parent_session(nil), do: {:ok, nil}

  defp validate_parent_session(id) do
    case Sessions.get_session(id) do
      {:ok, _} ->
        {:ok, id}

      {:error, :not_found} ->
        {:error, "parent_not_found", "parent_session_id #{id} does not exist"}
    end
  end
end

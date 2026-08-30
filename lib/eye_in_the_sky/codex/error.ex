defmodule EyeInTheSky.Codex.Error do
  @moduledoc """
  Normalizes Codex CLI error payloads into user-facing text and stable metadata.
  """

  alias EyeInTheSky.Redaction

  @type normalized :: %{
          message: String.t(),
          status: integer() | nil,
          error_type: String.t() | nil,
          model: String.t() | nil
        }

  @spec normalize(term(), String.t()) :: normalized()
  def normalize(payload, fallback \\ "Codex error")

  def normalize(payload, fallback) when is_binary(payload) do
    trimmed = String.trim(payload)

    case Jason.decode(trimmed) do
      {:ok, decoded} -> normalize(decoded, fallback)
      {:error, _} -> build(Redaction.redact(trimmed), nil, nil)
    end
  end

  def normalize(%{"type" => "error", "status" => status, "error" => error}, fallback) do
    normalized = normalize(error, fallback)
    %{normalized | status: status || normalized.status}
  end

  def normalize(%{"message" => message, "type" => type} = payload, _fallback)
      when is_binary(message) do
    build(message, payload["status"], type)
  end

  def normalize(%{"message" => message} = payload, _fallback) when is_binary(message) do
    build(message, payload["status"], payload["type"])
  end

  def normalize(%{"error" => error} = payload, fallback) do
    normalized = normalize(error, fallback)
    %{normalized | status: payload["status"] || normalized.status}
  end

  def normalize(payload, fallback) when is_map(payload) do
    build(fallback, payload["status"], payload["type"])
  end

  def normalize(other, fallback) do
    build(Redaction.redact_inspect(other || fallback, limit: 500), nil, nil)
  end

  @spec unsupported_model?(term()) :: boolean()
  def unsupported_model?(%{message: message}) when is_binary(message) do
    unsupported_model_message?(message)
  end

  def unsupported_model?(payload) do
    payload
    |> normalize()
    |> Map.get(:message)
    |> unsupported_model_message?()
  end

  defp unsupported_model_message?(message) when is_binary(message),
    do: message =~ ~r/model (is )?not supported|unsupported model|unknown model/iu

  defp unsupported_model_message?(_message), do: false

  defp build(message, status, error_type) do
    message = Redaction.redact(message || "Codex error")

    %{
      message: message,
      status: status,
      error_type: error_type,
      model: extract_model(message)
    }
  end

  defp extract_model(message) when is_binary(message) do
    case Regex.run(~r/The '([^']+)' model|model ['"]([^'"]+)['"]/i, message) do
      [_, model, ""] -> model
      [_, "", model] -> model
      [_, model] -> model
      _ -> nil
    end
  end
end

defmodule EyeInTheSkyWeb.Claude.OutputParser do
  @moduledoc """
  Parses Claude CLI JSON line outputs and extracts useful data.
  """

  @spec decode_line(String.t()) :: {:ok, map()} | {:error, any()}
  def decode_line(line) when is_binary(line) do
    # Strip ANSI escape codes before parsing JSON
    clean_line = String.replace(line, ~r/\e\[[0-9;]*[A-Za-z]/, "")
    Jason.decode(clean_line)
  end

  @doc """
  Extract assistant-visible text from parsed Claude JSON payloads.
  """
  @spec extract_text(map()) :: String.t() | nil
  def extract_text(parsed) when is_map(parsed) do
    cond do
      message = parsed["message"] ->
        extract_from_content_array(message["content"]) || parsed["text"] || parsed["body"]

      content = parsed["content"] ->
        extract_from_content_array(content) || parsed["text"] || parsed["body"]

      true ->
        parsed["text"] || parsed["body"]
    end
  end

  defp extract_from_content_array(content) when is_list(content) do
    content
    |> Enum.map(fn item ->
      case item do
        %{"type" => "text", "text" => text} ->
          text

        %{"type" => "tool_use", "name" => name, "input" => input} ->
          "Using #{name} with #{inspect(input)}"

        _ ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.join("\n")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_from_content_array(_), do: nil
end

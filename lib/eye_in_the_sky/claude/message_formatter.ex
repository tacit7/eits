defmodule EyeInTheSky.Claude.MessageFormatter do
  @moduledoc """
  Formats Claude session messages for UI display.

  Extracted from SessionReader — handles content extraction, tool-call
  summarization, and tool-result block emission.
  """

  @doc """
  Formats messages for the UI.
  Extracts role, content, and timestamp from Claude session JSON.
  Tool result blocks from "user" messages are emitted as separate entries.
  """
  def format_messages(messages) when is_list(messages) do
    count = Enum.count(messages)

    messages
    |> Enum.with_index()
    |> Enum.flat_map(fn {msg, idx} ->
      timestamp =
        msg["timestamp"] || msg["created_at"] ||
          DateTime.utc_now()
          |> DateTime.add(-count + idx, :second)
          |> DateTime.to_iso8601()

      tool_results = extract_tool_result_messages(msg, timestamp)

      base = %{
        uuid: msg["uuid"],
        role: get_in(msg, ["message", "role"]) || msg["type"],
        content: extract_content(msg),
        timestamp: timestamp,
        usage: get_in(msg, ["message", "usage"]),
        stream_type: nil
      }

      regular =
        if base.content == "" || String.starts_with?(String.trim(base.content), "<") do
          []
        else
          [base]
        end

      regular ++ tool_results
    end)
  end

  @doc """
  Returns a compact summary string for a tool call, suitable for chat display.
  """
  def format_tool_call("Read", %{"file_path" => path}), do: "> `Read` #{path}"
  def format_tool_call("Write", %{"file_path" => path}), do: "> `Write` #{path}"
  def format_tool_call("Edit", %{"file_path" => path}), do: "> `Edit` #{path}"
  def format_tool_call("Glob", %{"pattern" => pat}), do: "> `Glob` #{pat}"

  def format_tool_call("Grep", %{"pattern" => pat} = input) do
    path = input["path"] || ""
    "> `Grep` `#{pat}` #{path}"
  end

  def format_tool_call("Bash", %{"command" => cmd}) do
    "> `Bash` #{cmd}"
  end

  def format_tool_call("Task", %{"prompt" => prompt}) do
    truncated = String.slice(prompt, 0..80)
    suffix = if String.length(prompt) > 81, do: "...", else: ""
    "> `Task` #{truncated}#{suffix}"
  end

  def format_tool_call(name, %{"message" => msg} = input)
      when is_binary(name) and is_binary(msg) do
    voice = Map.get(input, "voice", "")
    rate = Map.get(input, "rate")

    parts =
      [
        "message: #{msg}",
        if(voice != "", do: "voice: #{voice}", else: nil),
        if(rate, do: "rate: #{rate}", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "> `#{name}` #{parts}"
  end

  def format_tool_call(name, input) when is_map(input) do
    summary =
      input
      |> Map.to_list()
      |> Enum.take(2)
      |> Enum.filter(fn {_k, v} -> is_binary(v) or is_number(v) or is_atom(v) end)
      |> Enum.map_join(", ", fn {k, v} ->
        val = v |> to_string() |> String.slice(0..500)
        "#{k}: #{val}"
      end)

    "> `#{name}` #{summary}"
  end

  def format_tool_call(name, _), do: "> `#{name}`"

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp extract_tool_result_messages(
         %{"type" => "user", "message" => %{"content" => content}} = _msg,
         timestamp
       )
       when is_list(content) do
    for block <- content, match?(%{"type" => "tool_result"}, block) do
      tool_use_id = block["tool_use_id"] || ""
      result_content = block["content"] || ""
      body = if is_binary(result_content), do: result_content, else: Jason.encode!(result_content)
      body = String.slice(body, 0..4000)

      %{
        uuid: derive_tool_result_uuid(tool_use_id),
        role: "tool_result",
        content: body,
        timestamp: timestamp,
        usage: nil,
        stream_type: "tool_result"
      }
    end
  end

  defp extract_tool_result_messages(_, _), do: []

  defp derive_tool_result_uuid(seed) when is_binary(seed) and seed != "" do
    hex = :crypto.hash(:sha, seed) |> Base.encode16(case: :lower)

    "#{String.slice(hex, 0, 8)}-#{String.slice(hex, 8, 4)}-#{String.slice(hex, 12, 4)}-#{String.slice(hex, 16, 4)}-#{String.slice(hex, 20, 12)}"
  end

  defp derive_tool_result_uuid(_), do: nil

  defp extract_content(%{"message" => %{"content" => content}}) when is_binary(content) do
    content
  end

  defp extract_content(%{"message" => %{"content" => content}}) when is_list(content) do
    extract_content_from_blocks(content)
  end

  # Handle case where content is directly in message (not nested)
  defp extract_content(%{"content" => content}) when is_binary(content) do
    content
  end

  defp extract_content(%{"content" => content}) when is_list(content) do
    extract_content_from_blocks(content)
  end

  defp extract_content(_), do: ""

  defp extract_content_from_blocks(content) do
    content
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} ->
        [text]

      %{"type" => "tool_use", "name" => name, "input" => input} ->
        [format_tool_call(name, input)]

      _ ->
        []
    end)
    |> Enum.join("\n\n")
  end
end

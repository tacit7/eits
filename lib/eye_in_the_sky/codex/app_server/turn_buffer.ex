defmodule EyeInTheSky.Codex.AppServer.TurnBuffer do
  @moduledoc false

  alias EyeInTheSky.Claude.Message

  defstruct text: "",
            text_item_id: nil,
            thinking: "",
            thinking_item_id: nil,
            parts: [],
            command_outputs: %{}

  @type t :: %__MODULE__{}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec apply_notification(t(), String.t(), map()) :: {t(), [Message.t()]}
  def apply_notification(%__MODULE__{} = buffer, method, params) do
    case method do
      "item/agentMessage/delta" ->
        apply_text_delta(buffer, string(params, "itemId"), string(params, "delta"))

      "item/reasoning/textDelta" ->
        apply_thinking_delta(buffer, string(params, "itemId"), string(params, "delta"))

      "item/reasoning/summaryTextDelta" ->
        apply_thinking_delta(buffer, string(params, "itemId"), string(params, "delta"))

      "item/commandExecution/outputDelta" ->
        apply_command_output_delta(buffer, string(params, "itemId"), string(params, "delta"))

      "item/completed" ->
        apply_item_completed(buffer, params["item"] || %{})

      _ ->
        {buffer, []}
    end
  end

  @spec drain(t()) :: {t(), [Message.t()]}
  def drain(%__MODULE__{} = buffer) do
    {buffer, thinking_messages} = flush_thinking(buffer)
    {buffer, text_messages} = flush_text(buffer)
    {%{buffer | command_outputs: %{}}, thinking_messages ++ text_messages}
  end

  @spec result_text(t()) :: String.t() | nil
  def result_text(%__MODULE__{parts: parts}) do
    parts
    |> Enum.reverse()
    |> Enum.map(fn
      {:text, text} -> text
      {:tool, text} -> text
      {:thinking, _text} -> ""
    end)
    |> Enum.join("")
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp apply_text_delta(buffer, item_id, ""), do: maybe_rotate_text(buffer, item_id)

  defp apply_text_delta(buffer, item_id, delta) do
    {buffer, flushed} = maybe_rotate_text(buffer, item_id)
    buffer = %{buffer | text: buffer.text <> delta, text_item_id: item_id}
    {buffer, flushed ++ [Message.text(delta, true)]}
  end

  defp apply_thinking_delta(buffer, item_id, ""), do: maybe_rotate_thinking(buffer, item_id)

  defp apply_thinking_delta(buffer, item_id, delta) do
    {buffer, flushed} = maybe_rotate_thinking(buffer, item_id)
    buffer = %{buffer | thinking: buffer.thinking <> delta, thinking_item_id: item_id}
    {buffer, flushed ++ [Message.thinking(delta, true)]}
  end

  defp apply_command_output_delta(buffer, item_id, delta) do
    output = Map.get(buffer.command_outputs, item_id, "") <> delta

    message =
      Message.tool_use(
        "command_execution_output",
        %{item_id: item_id, output: output},
        %{partial: true}
      )

    {%{buffer | command_outputs: Map.put(buffer.command_outputs, item_id, output)}, [message]}
  end

  defp apply_item_completed(buffer, %{"type" => "agentMessage", "id" => item_id})
       when item_id == buffer.text_item_id do
    flush_text(buffer)
  end

  defp apply_item_completed(buffer, %{"type" => "reasoning", "id" => item_id})
       when item_id == buffer.thinking_item_id do
    flush_thinking(buffer)
  end

  defp apply_item_completed(buffer, %{"type" => "commandExecution"} = item) do
    command = string(item, "command")

    input = %{
      command: command,
      exit_code: item["exitCode"],
      output: item["aggregatedOutput"] || item["output"],
      working_directory: item["cwd"]
    }

    summary =
      if command == "" do
        ""
      else
        "> `Bash` #{command}\n"
      end

    buffer =
      if summary == "", do: buffer, else: %{buffer | parts: [{:tool, summary} | buffer.parts]}

    {buffer, [Message.tool_use("command_execution", input)]}
  end

  defp apply_item_completed(buffer, %{"type" => "fileChange"} = item) do
    {buffer, [Message.tool_use("file_change", item)]}
  end

  defp apply_item_completed(buffer, %{"type" => "mcpToolCall"} = item) do
    {buffer, [Message.tool_use(mcp_tool_name(item), item)]}
  end

  defp apply_item_completed(buffer, _item), do: {buffer, []}

  defp maybe_rotate_text(buffer, item_id) do
    if buffer.text_item_id && buffer.text_item_id != item_id do
      flush_text(buffer)
    else
      {buffer, []}
    end
  end

  defp maybe_rotate_thinking(buffer, item_id) do
    if buffer.thinking_item_id && buffer.thinking_item_id != item_id do
      flush_thinking(buffer)
    else
      {buffer, []}
    end
  end

  defp flush_text(%__MODULE__{text: text} = buffer) do
    if String.trim(text) == "" do
      {%{buffer | text: "", text_item_id: nil}, []}
    else
      buffer = %{buffer | text: "", text_item_id: nil, parts: [{:text, text} | buffer.parts]}
      {buffer, [Message.text(text, false)]}
    end
  end

  defp flush_thinking(%__MODULE__{thinking: thinking} = buffer) do
    if String.trim(thinking) == "" do
      {%{buffer | thinking: "", thinking_item_id: nil}, []}
    else
      buffer = %{
        buffer
        | thinking: "",
          thinking_item_id: nil,
          parts: [{:thinking, thinking} | buffer.parts]
      }

      {buffer, [Message.thinking(thinking, false)]}
    end
  end

  defp mcp_tool_name(item) do
    server = item |> string("server") |> sanitize_tool_segment()
    tool = item |> string("tool") |> sanitize_tool_segment()
    "mcp__#{server}__#{tool}"
  end

  defp string(map, key) when is_map(map), do: Map.get(map, key, "") || ""
  defp string(_, _), do: ""

  defp sanitize_tool_segment(""), do: "unknown"

  defp sanitize_tool_segment(value) do
    String.replace(value, ~r/[^A-Za-z0-9_-]/, "_")
  end
end

defmodule EyeInTheSky.Codex.ToolMapper do
  @moduledoc """
  Normalizes Codex tool calls into the format expected by MessageFormatter.
  """

  alias EyeInTheSky.Claude.MessageFormatter

  @doc """
  Format a Codex tool call name and input into a human-readable summary.
  Returns an empty string for non-binary names.
  """
  @spec format_codex_tool_summary(term(), term()) :: String.t()
  def format_codex_tool_summary(name, input) when is_binary(name) do
    {tool_name, tool_input} = normalize_codex_tool(name, input)
    MessageFormatter.format_tool_call(tool_name, tool_input)
  end

  def format_codex_tool_summary(_name, _input), do: ""

  @doc """
  Normalize a Codex tool name and input map to a canonical {name, input} pair.
  """
  @spec normalize_codex_tool(String.t(), term()) :: {String.t(), map()}
  def normalize_codex_tool("command_execution", input) do
    command = get_field(input, "command")
    {"Bash", %{"command" => command || ""}}
  end

  def normalize_codex_tool(name, input) when name in ["web_search", "web_searches"] do
    query = get_field(input, "query")
    {"WebSearch", %{"query" => query || ""}}
  end

  def normalize_codex_tool(name, input) when name in ["plan_update", "plan_updates"] do
    summary =
      get_field(input, "summary") ||
        get_field(input, "explanation") ||
        get_field(input, "plan") ||
        inspect(input)

    {"Task", %{"prompt" => to_string(summary)}}
  end

  def normalize_codex_tool(name, input) when name in ["mcp_tool_call", "mcp_tool_calls"] do
    server = get_field(input, "server") || "mcp"
    tool = get_field(input, "tool") || "tool"
    {"mcp_#{server}__#{tool}", stringify_map(input)}
  end

  def normalize_codex_tool(name, input), do: {name, stringify_map(input)}

  defp get_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {k, v} when is_atom(k) ->
          if Atom.to_string(k) == key, do: v, else: nil

        _ ->
          nil
      end)
  end

  defp get_field(_map, _key), do: nil

  defp stringify_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), v)
      {k, v}, acc when is_binary(k) -> Map.put(acc, k, v)
      {k, v}, acc -> Map.put(acc, to_string(k), v)
    end)
  end

  defp stringify_map(_), do: %{}
end

defmodule EyeInTheSky.AgentDefinitions.FrontmatterParser do
  @moduledoc """
  Parses YAML-like frontmatter from agent `.md` files.
  """

  @doc """
  Parses YAML-like frontmatter from an agent `.md` file.
  Returns a map with `:display_name`, `:description`, `:model`, `:tools`.
  """
  def parse_frontmatter(content) do
    case Regex.run(~r/\A---\n(.*?)\n---/s, content) do
      [_, yaml_block] ->
        lines = String.split(yaml_block, "\n")

        {raw_attrs, _current_key} =
          Enum.reduce(lines, {%{}, nil}, fn line, {acc, current_key} ->
            classify_yaml_line(String.trim(line), acc, current_key)
          end)

        attrs =
          Map.new(raw_attrs, fn {k, v} -> {k, if(is_list(v), do: Enum.reverse(v), else: v)} end)

        %{
          display_name: attrs["name"],
          description: extract_description(attrs["description"]),
          model: attrs["model"],
          tools: parse_tools(attrs["tools"])
        }

      _ ->
        %{display_name: nil, description: nil, model: nil, tools: []}
    end
  end

  defp classify_yaml_line(trimmed, acc, current_key) do
    case {Regex.run(~r/^(\w+):\s+(.+)$/, trimmed), Regex.run(~r/^(\w+):\s*$/, trimmed),
          Regex.run(~r/^-\s+(.+)$/, trimmed)} do
      {[_, key, value], _, _} ->
        {Map.put(acc, key, clean_value(value)), key}

      {nil, [_, key], _} ->
        {Map.put(acc, key, []), key}

      {nil, nil, [_, value]} ->
        {append_list_item(acc, current_key, value), current_key}

      _ ->
        {acc, current_key}
    end
  end

  defp append_list_item(acc, nil, _value), do: acc

  defp append_list_item(acc, current_key, value) do
    existing = Map.get(acc, current_key, [])
    items = if is_list(existing), do: existing, else: []
    Map.put(acc, current_key, [clean_value(value) | items])
  end

  defp clean_value(value) do
    value |> String.trim() |> String.trim("\"") |> String.trim("'")
  end

  defp extract_description(nil), do: nil

  defp extract_description(desc) do
    desc |> String.split("\\n") |> List.first() |> String.trim()
  end

  defp parse_tools(nil), do: []
  defp parse_tools(tools) when is_list(tools), do: Enum.map(tools, &String.trim/1)

  defp parse_tools(tools_str) when is_binary(tools_str) do
    tools_str |> String.split(~r/[,\s]+/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end
end

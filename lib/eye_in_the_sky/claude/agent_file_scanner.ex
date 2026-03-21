defmodule EyeInTheSky.Claude.AgentFileScanner do
  @moduledoc """
  Scans .claude/agents/ directories for agent definition files (.md with YAML frontmatter).
  Returns maps compatible with Prompt struct fields for use anywhere agents need listing.

  Filesystem agents use string IDs prefixed with "fs:" to distinguish from DB prompts.
  """

  @doc """
  Scans both project-level and global agent directories.
  Returns a list of maps with keys: id, name, description, prompt_text, project_id, source, model, tools, color.

  - Project agents: `{project_path}/.claude/agents/*.md`
  - Global agents: `~/.claude/agents/*.md`

  Project agents take precedence over global agents with the same name.
  """
  def scan(project_path \\ nil) do
    project_agents =
      if project_path do
        dir = Path.join(project_path, ".claude/agents")
        scan_directory(dir, :project)
      else
        []
      end

    global_agents = scan_directory(global_agents_dir(), :global)

    seen = MapSet.new(project_agents, & &1.name)

    project_agents ++
      Enum.reject(global_agents, fn a -> MapSet.member?(seen, a.name) end)
  end

  @doc """
  Finds a filesystem agent by its string ID (e.g., "fs:/path/to/agent.md").
  Returns nil if the ID is not a filesystem ID or the file doesn't exist.
  """
  def get_by_id("fs:" <> path) do
    if allowed_agent_path?(path) and File.regular?(path) do
      parse_agent_file(path, :unknown)
    else
      nil
    end
  end

  def get_by_id(_), do: nil

  @doc """
  Returns true if the given ID is a filesystem agent ID.
  """
  def filesystem_id?("fs:" <> _), do: true
  def filesystem_id?(_), do: false

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp allowed_agent_path?(path) do
    expanded = Path.expand(path)
    dir = Path.dirname(expanded)
    global = global_agents_dir()

    # Must be a .md file directly inside an agents directory (no subdirectory traversal)
    String.ends_with?(expanded, ".md") and
      (dir == global or String.ends_with?(dir, "/.claude/agents"))
  end

  defp global_agents_dir do
    Path.expand("~/.claude/agents")
  end

  defp scan_directory(dir, source) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reject(&(&1 == "README.md"))
        |> Enum.sort()
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.map(&parse_agent_file(&1, source))
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp parse_agent_file(path, source) do
    case File.read(path) do
      {:ok, content} ->
        case parse_frontmatter(content) do
          {:ok, meta, body} ->
            %{
              id: "fs:#{path}",
              name: meta["name"] || Path.basename(path, ".md"),
              description: meta["description"] || "",
              prompt_text: String.trim(body),
              project_id: nil,
              source: source,
              model: meta["model"],
              tools: meta["tools"],
              color: meta["color"]
            }

          :error ->
            nil
        end

      {:error, _} ->
        nil
    end
  end

  defp parse_frontmatter(content) do
    case String.split(content, ~r/\n---\s*\n/, parts: 2) do
      ["---" <> yaml_raw, body] ->
        case parse_yaml(yaml_raw) do
          {:ok, meta} -> {:ok, meta, body}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_yaml(yaml_str) do
    pairs =
      yaml_str
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.reduce(%{}, fn line, acc ->
        case Regex.run(~r/^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.*)$/, line) do
          [_, key, raw_val] ->
            val = raw_val |> unquote_yaml_value() |> String.trim()
            Map.put(acc, key, val)

          _ ->
            acc
        end
      end)

    if map_size(pairs) > 0, do: {:ok, pairs}, else: :error
  end

  defp unquote_yaml_value(val) do
    cond do
      String.starts_with?(val, "\"") and String.ends_with?(val, "\"") ->
        val |> String.slice(1..-2//1) |> String.replace("\\n", "\n")

      String.starts_with?(val, "'") and String.ends_with?(val, "'") ->
        String.slice(val, 1..-2//1)

      true ->
        val
    end
  end
end

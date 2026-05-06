defmodule EyeInTheSkyWeb.Helpers.SlashItems do
  @moduledoc """
  Loads slash command, skill, agent, and prompt items for the DM composer popup.
  """

  alias EyeInTheSky.{Agents, Prompts, Sessions}
  alias EyeInTheSkyWeb.DmLive.SlashCommands

  @doc """
  Returns a flat list of slash-completable items from all sources:
  - Skills and commands from disk (~/.claude/skills/, ~/.claude/commands/)
  - Plugin skills from ~/.claude/plugins/cache/ (enabled in settings.json)
  - Project-level skills from <project>/.claude/skills/
  - Agents from the database
  - Prompts from the database
  """
  def build(opts \\ []) do
    commands_dir = Keyword.get(opts, :commands_dir, Path.expand("~/.claude/commands"))
    skills_dir = Keyword.get(opts, :skills_dir, Path.expand("~/.claude/skills"))
    plugins_dir = Keyword.get(opts, :plugins_dir, Path.expand("~/.claude/plugins"))
    settings_path = Keyword.get(opts, :settings_path, Path.expand("~/.claude/settings.json"))
    project_path = Keyword.get(opts, :project_path, nil)

    skills = load_skills(commands_dir, skills_dir)
    plugin_skills = load_plugin_skills(plugins_dir, settings_path)
    project_skills = load_project_skills(project_path)
    agents = load_agents()
    prompts = load_prompts()
    flags = cli_flags()

    (skills ++ plugin_skills ++ project_skills ++ agents ++ prompts ++ flags)
    |> Enum.uniq_by(& &1.slug)
  end

  @doc """
  Returns a list of CLI flag items derived from SlashCommands.command_metadata/0.
  Each item has slug, type: "flag", description, and arg_type.
  """
  def cli_flags do
    SlashCommands.command_metadata()
    |> Enum.map(fn {slug, arg_type, description} ->
      %{slug: slug, type: "flag", description: description, arg_type: encode_arg_type(arg_type)}
    end)
  end

  defp encode_arg_type(:none), do: "none"
  defp encode_arg_type(:free_text), do: "free_text"
  defp encode_arg_type(:integer), do: "integer"
  defp encode_arg_type(:path), do: "path"
  defp encode_arg_type({:enum, values}), do: %{type: "enum", values: values}

  @doc false
  def load_skills(commands_dir, skills_dir) do
    commands = load_commands(commands_dir)
    skills = load_skill_dirs(skills_dir)
    commands ++ skills
  end

  defp load_commands(commands_dir) do
    if File.dir?(commands_dir) do
      case File.ls(commands_dir) do
        {:ok, entries} -> Enum.flat_map(entries, &load_command_entry(commands_dir, &1))
        {:error, _} -> []
      end
    else
      []
    end
  end

  defp load_command_entry(commands_dir, entry) do
    path = Path.join(commands_dir, entry)

    cond do
      String.ends_with?(entry, ".md") and File.regular?(path) ->
        slug = String.replace_trailing(entry, ".md", "")

        case File.read(path) do
          {:ok, content} ->
            [%{slug: slug, type: "command", description: extract_description(content)}]

          {:error, _} ->
            []
        end

      File.dir?(path) ->
        sub_entries =
          case File.ls(path) do
            {:ok, entries} -> entries
            {:error, _} -> []
          end

        sub_entries
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.flat_map(fn filename ->
          subslug = "#{entry}:#{String.replace_trailing(filename, ".md", "")}"

          case File.read(Path.join(path, filename)) do
            {:ok, content} ->
              [%{slug: subslug, type: "command", description: extract_description(content)}]

            {:error, _} ->
              []
          end
        end)

      true ->
        []
    end
  end

  defp load_skill_dirs(skills_dir) do
    if File.dir?(skills_dir) do
      case File.ls(skills_dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn dir ->
            Path.join([skills_dir, dir, "SKILL.md"]) |> File.exists?()
          end)
          |> Enum.flat_map(fn dir ->
            case File.read(Path.join([skills_dir, dir, "SKILL.md"])) do
              {:ok, content} ->
                [%{slug: dir, type: "skill", description: extract_description(content)}]

              {:error, _} ->
                []
            end
          end)

        {:error, _} ->
          []
      end
    else
      []
    end
  end

  @doc false
  def load_plugin_skills(plugins_dir, settings_path) do
    enabled = read_enabled_plugins(settings_path)

    if map_size(enabled) == 0 do
      []
    else
      cache_dir = Path.join(plugins_dir, "cache")
      load_enabled_plugin_skills(cache_dir, enabled)
    end
  end

  defp load_enabled_plugin_skills(cache_dir, enabled) do
    if File.dir?(cache_dir) do
      Enum.flat_map(enabled, fn {key, true} -> load_plugin_by_key(cache_dir, key) end)
    else
      []
    end
  end

  defp load_plugin_by_key(cache_dir, key) do
    # Key format: "plugin-name@registry-name"
    case String.split(key, "@", parts: 2) do
      [plugin_name, registry] ->
        plugin_dir = Path.join([cache_dir, registry, plugin_name])

        if File.dir?(plugin_dir) do
          load_plugin_versions(plugin_dir, plugin_name)
        else
          []
        end

      _ ->
        []
    end
  end

  defp load_plugin_versions(plugin_dir, plugin_name) do
    versions =
      case File.ls(plugin_dir) do
        {:ok, entries} -> entries
        {:error, _} -> []
      end

    versions
    |> Enum.flat_map(fn version ->
      skills_dir = Path.join([plugin_dir, version, "skills"])
      load_skills_from_version_dir(skills_dir, plugin_name)
    end)
    |> Enum.uniq_by(& &1.slug)
  end

  defp load_skills_from_version_dir(skills_dir, plugin_name) do
    if File.dir?(skills_dir) do
      case File.ls(skills_dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn skill_name ->
            Path.join([skills_dir, skill_name, "SKILL.md"]) |> File.exists?()
          end)
          |> Enum.flat_map(fn skill_name ->
            case File.read(Path.join([skills_dir, skill_name, "SKILL.md"])) do
              {:ok, content} ->
                slug = "#{plugin_name}:#{skill_name}"
                [%{slug: slug, type: "skill", description: extract_description(content)}]

              {:error, _} ->
                []
            end
          end)

        {:error, _} ->
          []
      end
    else
      []
    end
  end

  defp read_enabled_plugins(settings_path) do
    case File.read(settings_path) do
      {:ok, content} -> parse_enabled_plugins(content)
      _ -> %{}
    end
  end

  defp parse_enabled_plugins(content) do
    case Jason.decode(content) do
      {:ok, %{"enabledPlugins" => plugins}} when is_map(plugins) ->
        plugins |> Enum.filter(fn {_k, v} -> v end) |> Map.new()

      _ ->
        %{}
    end
  end

  @doc false
  def load_project_skills(nil), do: []

  def load_project_skills(project_path) do
    skills_dir = Path.join([project_path, ".claude", "skills"])
    load_skill_dirs(skills_dir)
  end

  @doc false
  def load_agents do
    agents = Agents.list_agents()
    agent_ids = Enum.map(agents, & &1.id)

    # Query most recent session_id per agent for @mention autocomplete.
    session_map = Sessions.latest_session_id_by_agents(agent_ids)

    agents
    |> Enum.map(fn agent ->
      slug = agent.project_name || agent.description || "agent-#{agent.id}"

      %{
        slug: String.slice(slug, 0, 60),
        type: "agent",
        description: agent.description || agent.project_name || "",
        session_id: Map.get(session_map, agent.id)
      }
    end)
    |> Enum.uniq_by(& &1.slug)
  end

  @doc false
  def load_prompts do
    Prompts.list_prompts()
    |> Enum.map(fn prompt ->
      slug = prompt.slug || prompt.name

      if is_nil(slug) or slug == "" do
        nil
      else
        %{
          slug: slug,
          type: "prompt",
          description: prompt.description || ""
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc false
  def extract_description(content) do
    case Regex.run(~r/^---\n(.*?)\n---/s, content) do
      [_, frontmatter] ->
        case Regex.run(~r/description:\s*"?([^"\n]+)"?/, frontmatter) do
          [_, desc] -> String.trim(desc)
          _ -> extract_first_heading(content)
        end

      _ ->
        extract_first_heading(content)
    end
  end

  defp extract_first_heading(content) do
    content
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "#"))
    |> case do
      nil -> ""
      line -> String.replace(line, ~r/^#+\s*/, "") |> String.trim()
    end
  end
end

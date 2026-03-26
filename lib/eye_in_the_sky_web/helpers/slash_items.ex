defmodule EyeInTheSkyWeb.Helpers.SlashItems do
  @moduledoc """
  Loads slash command, skill, agent, and prompt items for the DM composer popup.
  """

  alias EyeInTheSky.{Agents, Prompts}

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
  Returns hardcoded CLI flag slash items. These map to Claude CLI flags that can
  be injected inline into DM messages to control how the next invocation runs.
  """
  def cli_flags do
    [
      # Session & Context
      %{slug: "add-dir", type: "flag", description: "Add extra working directory --add-dir <path>"},
      %{slug: "rename", type: "flag", description: "Rename this session --name <name>"},
      # Model & Performance
      %{slug: "model", type: "flag", description: "Set model for this message --model <model>"},
      %{slug: "effort", type: "flag", description: "Set effort level: low|medium|high|max"},
      %{slug: "plan", type: "flag", description: "Force plan-only mode, no file changes"},
      %{slug: "max-turns", type: "flag", description: "Limit agentic steps --max-turns <n>"},
      # Permissions
      %{slug: "permissions", type: "flag", description: "Set permission mode --permission-mode <mode>"},
      %{slug: "sandbox", type: "flag", description: "Enable OS-level sandbox isolation"},
      %{slug: "no-sandbox", type: "flag", description: "Disable OS-level sandbox isolation"},
      # Tools & Integrations
      %{slug: "agents", type: "flag", description: "Run as named subagent --agent <name>"},
      %{slug: "chrome", type: "flag", description: "Enable browser automation"},
      %{slug: "no-chrome", type: "flag", description: "Disable browser automation"},
      %{slug: "mcp", type: "flag", description: "Load MCP config file --mcp-config <file>"},
      %{slug: "plugin", type: "flag", description: "Load plugins from directory --plugin-dir <path>"},
      # Configuration
      %{slug: "config", type: "flag", description: "Load settings from file --settings <file>"},
    ]
  end

  @doc false
  def load_skills(commands_dir, skills_dir) do
    commands = load_commands(commands_dir)
    skills = load_skill_dirs(skills_dir)
    commands ++ skills
  end

  defp load_commands(commands_dir) do
    if File.dir?(commands_dir) do
      commands_dir
      |> File.ls!()
      |> Enum.flat_map(fn entry ->
        path = Path.join(commands_dir, entry)

        cond do
          String.ends_with?(entry, ".md") and File.regular?(path) ->
            slug = String.replace_trailing(entry, ".md", "")
            content = File.read!(path)
            [%{slug: slug, type: "command", description: extract_description(content)}]

          File.dir?(path) ->
            path
            |> File.ls!()
            |> Enum.filter(&String.ends_with?(&1, ".md"))
            |> Enum.map(fn filename ->
              subslug = "#{entry}:#{String.replace_trailing(filename, ".md", "")}"
              content = File.read!(Path.join(path, filename))
              %{slug: subslug, type: "command", description: extract_description(content)}
            end)

          true ->
            []
        end
      end)
    else
      []
    end
  end

  defp load_skill_dirs(skills_dir) do
    if File.dir?(skills_dir) do
      skills_dir
      |> File.ls!()
      |> Enum.filter(fn dir ->
        Path.join([skills_dir, dir, "SKILL.md"]) |> File.exists?()
      end)
      |> Enum.map(fn dir ->
        content = File.read!(Path.join([skills_dir, dir, "SKILL.md"]))
        %{slug: dir, type: "skill", description: extract_description(content)}
      end)
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

      if File.dir?(cache_dir) do
        enabled
        |> Enum.flat_map(fn {key, true} ->
          # Key format: "plugin-name@registry-name"
          case String.split(key, "@", parts: 2) do
            [plugin_name, registry] ->
              registry_dir = Path.join(cache_dir, registry)
              plugin_dir = Path.join(registry_dir, plugin_name)

              if File.dir?(plugin_dir) do
                # Find the first version dir that has skills
                plugin_dir
                |> File.ls!()
                |> Enum.flat_map(fn version ->
                  skills_dir = Path.join([plugin_dir, version, "skills"])

                  if File.dir?(skills_dir) do
                    skills_dir
                    |> File.ls!()
                    |> Enum.filter(fn skill_name ->
                      Path.join([skills_dir, skill_name, "SKILL.md"]) |> File.exists?()
                    end)
                    |> Enum.map(fn skill_name ->
                      content = File.read!(Path.join([skills_dir, skill_name, "SKILL.md"]))
                      slug = "#{plugin_name}:#{skill_name}"

                      %{slug: slug, type: "skill", description: extract_description(content)}
                    end)
                  else
                    []
                  end
                end)
                |> Enum.uniq_by(& &1.slug)
              else
                []
              end

            _ ->
              []
          end
        end)
      else
        []
      end
    end
  end

  defp read_enabled_plugins(settings_path) do
    case File.read(settings_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"enabledPlugins" => plugins}} when is_map(plugins) ->
            plugins |> Enum.filter(fn {_k, v} -> v == true end) |> Map.new()

          _ ->
            %{}
        end

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
    Agents.list_agents()
    |> Enum.map(fn agent ->
      slug = agent.project_name || agent.description || "agent-#{agent.id}"

      %{
        slug: String.slice(slug, 0, 60),
        type: "agent",
        description: agent.description || agent.project_name || ""
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

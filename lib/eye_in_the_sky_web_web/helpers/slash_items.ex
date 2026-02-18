defmodule EyeInTheSkyWebWeb.Helpers.SlashItems do
  @moduledoc """
  Loads slash command, skill, agent, and prompt items for the DM composer popup.
  """

  alias EyeInTheSkyWeb.{Agents, Prompts}

  @doc """
  Returns a flat list of slash-completable items from all sources:
  - Skills and commands from disk (~/.claude/skills/, ~/.claude/commands/)
  - Agents from the database
  - Prompts from the database
  """
  def build(opts \\ []) do
    commands_dir = Keyword.get(opts, :commands_dir, Path.expand("~/.claude/commands"))
    skills_dir = Keyword.get(opts, :skills_dir, Path.expand("~/.claude/skills"))

    skills = load_skills(commands_dir, skills_dir)
    agents = load_agents()
    prompts = load_prompts()

    skills ++ agents ++ prompts
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

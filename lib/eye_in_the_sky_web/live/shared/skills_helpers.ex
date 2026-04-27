defmodule EyeInTheSkyWeb.Live.Shared.SkillsHelpers do
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.OverviewLive.Skills.Skill

  def load_skills(socket) do
    skills = do_load_skills()
    filtered = apply_filters_and_sort(skills, socket.assigns)

    socket
    |> assign(:skills, skills)
    |> assign(:filtered_skills, filtered)
  end

  def handle_search(%{"query" => query}, socket, reload_fn) do
    {:noreply, socket |> assign(:search_query, query) |> reload_fn.()}
  end

  def handle_sort_skills(%{"by" => by}, socket, reload_fn) do
    {:noreply, socket |> assign(:sort_by, by) |> reload_fn.()}
  end

  def handle_filter_source(%{"filter" => source}, socket, reload_fn) do
    {:noreply, socket |> assign(:source_filter, source) |> reload_fn.()}
  end

  def apply_filters_and_sort(skills, assigns) do
    skills
    |> filter_by_source(assigns.source_filter)
    |> filter_by_search(assigns.search_query)
    |> sort_skills(assigns.sort_by)
  end

  defp filter_by_source(skills, "all"), do: skills

  defp filter_by_source(skills, source) do
    Enum.filter(skills, &(to_string(&1.source) == source))
  end

  defp filter_by_search(skills, ""), do: skills

  defp filter_by_search(skills, query) do
    q = String.downcase(query)

    Enum.filter(skills, fn skill ->
      String.contains?(String.downcase(skill.slug), q) ||
        String.contains?(String.downcase(skill.description), q)
    end)
  end

  defp sort_skills(skills, "name_desc"), do: Enum.sort_by(skills, & &1.slug, :desc)
  defp sort_skills(skills, "size_desc"), do: Enum.sort_by(skills, & &1.size, :desc)
  defp sort_skills(skills, "size_asc"), do: Enum.sort_by(skills, & &1.size)
  defp sort_skills(skills, "recent"), do: Enum.sort_by(skills, & &1.mtime, :desc)
  defp sort_skills(skills, _), do: Enum.sort_by(skills, & &1.slug)

  defp do_load_skills do
    global_commands = load_from_dir(Path.expand("~/.claude/commands"), :commands)
    global_skills = load_from_skills_dir(Path.expand("~/.claude/skills"), :skills)
    project_commands = load_from_dir(Path.join(File.cwd!(), ".claude/commands"), :project)
    project_skills = load_from_skills_dir(Path.join(File.cwd!(), ".claude/skills"), :project)

    (global_commands ++ global_skills ++ project_commands ++ project_skills)
    |> Enum.sort_by(& &1.slug)
  end

  defp load_from_dir(dir, source) do
    if File.dir?(dir) do
      case File.ls(dir) do
        {:error, _} ->
          []

        {:ok, entries} ->
          entries
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.flat_map(fn filename ->
            path = Path.join(dir, filename)
            slug = String.replace_trailing(filename, ".md", "")

            case File.read(path) do
              {:error, _} ->
                []

              {:ok, content} ->
                stat = File.stat!(path)

                [
                  %Skill{
                    slug: slug,
                    filename: filename,
                    source: source,
                    description: extract_description(content),
                    content: content,
                    size: byte_size(content),
                    mtime: stat.mtime
                  }
                ]
            end
          end)
      end
    else
      []
    end
  end

  defp load_from_skills_dir(skills_dir, source) do
    if File.dir?(skills_dir) do
      case File.ls(skills_dir) do
        {:error, _} ->
          []

        {:ok, entries} ->
          entries
          |> Enum.filter(fn dir ->
            Path.join([skills_dir, dir, "SKILL.md"]) |> File.exists?()
          end)
          |> Enum.flat_map(fn dir ->
            path = Path.join([skills_dir, dir, "SKILL.md"])

            case File.read(path) do
              {:error, _} ->
                []

              {:ok, content} ->
                stat = File.stat!(path)

                [
                  %Skill{
                    slug: dir,
                    filename: "skills/#{dir}/SKILL.md",
                    source: source,
                    description: extract_description(content),
                    content: content,
                    size: byte_size(content),
                    mtime: stat.mtime
                  }
                ]
            end
          end)
      end
    else
      []
    end
  end

  defp extract_description(content) do
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
      nil -> "No description"
      line -> String.replace(line, ~r/^#+\s*/, "") |> String.trim()
    end
  end
end

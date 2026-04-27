defmodule EyeInTheSkyWeb.Live.Shared.SkillsHelpers do
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.OverviewLive.Skills.Skill

  def load_skills(socket) do
    project_path = project_path_for(socket)
    skills = do_load_skills(project_path)
    filtered = apply_filters_and_sort(skills, socket.assigns)

    socket
    |> assign(:skills, skills)
    |> assign(:filtered_skills, filtered)
  end

  defp project_path_for(socket) do
    case socket.assigns[:project] do
      %{path: path} when is_binary(path) and path != "" -> path
      _ -> File.cwd!()
    end
  end

  def handle_search(%{"query" => query}, socket, reload_fn) do
    {:noreply, socket |> assign(:search_query, query) |> reload_fn.()}
  end

  def handle_sort_skills(%{"by" => by}, socket, reload_fn) do
    {:noreply, socket |> assign(:sort_by, by) |> reload_fn.()}
  end

  def handle_filter_type(%{"filter" => type}, socket, reload_fn) do
    {:noreply, socket |> assign(:type_filter, type) |> reload_fn.()}
  end

  def handle_filter_scope(%{"scope" => scope}, socket, reload_fn) do
    {:noreply, socket |> assign(:scope_filter, scope) |> reload_fn.()}
  end

  def apply_filters_and_sort(skills, assigns) do
    skills
    |> filter_by_type(assigns.type_filter)
    |> filter_by_scope(assigns.scope_filter)
    |> filter_by_search(assigns.search_query)
    |> sort_skills(assigns.sort_by)
  end

  defp filter_by_type(skills, "all"), do: skills

  defp filter_by_type(skills, "skills") do
    Enum.filter(skills, &(&1.source in [:skills, :project_skills]))
  end

  defp filter_by_type(skills, "commands") do
    Enum.filter(skills, &(&1.source in [:commands, :project_commands]))
  end

  defp filter_by_type(skills, _), do: skills

  defp filter_by_scope(skills, "all"), do: skills

  defp filter_by_scope(skills, "global") do
    Enum.filter(skills, &(&1.source in [:skills, :commands]))
  end

  defp filter_by_scope(skills, "project") do
    Enum.filter(skills, &(&1.source in [:project_skills, :project_commands]))
  end

  defp filter_by_scope(skills, _), do: skills

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

  defp do_load_skills(project_path) do
    global_commands = load_from_dir(Path.expand("~/.claude/commands"), :commands, "~/.claude/commands")
    global_skills = load_from_skills_dir(Path.expand("~/.claude/skills"), :skills, "~/.claude/skills")
    project_commands = load_from_dir(Path.join(project_path, ".claude/commands"), :project_commands, ".claude/commands")
    project_skills = load_from_skills_dir(Path.join(project_path, ".claude/skills"), :project_skills, ".claude/skills")

    (global_commands ++ global_skills ++ project_commands ++ project_skills)
    |> Enum.sort_by(& &1.slug)
  end

  defp build_id(source, slug), do: "#{source}:#{slug}"

  defp load_from_dir(dir, source, display_prefix) do
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
                    id: build_id(source, slug),
                    slug: slug,
                    filename: filename,
                    path: "#{display_prefix}/#{filename}",
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

  defp load_from_skills_dir(skills_dir, source, display_prefix) do
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
                    id: build_id(source, dir),
                    slug: dir,
                    filename: "SKILL.md",
                    path: "#{display_prefix}/#{dir}/SKILL.md",
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

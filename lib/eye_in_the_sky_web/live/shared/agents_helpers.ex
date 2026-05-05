defmodule EyeInTheSkyWeb.Live.Shared.AgentsHelpers do
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.OverviewLive.Agents.AgentDef

  @doc """
  Loads agents for the rail flyout.
  When project is nil, returns global agents (~/.claude/agents) capped at 15.
  When project is set, returns project-scoped agents (.claude/agents) capped at 15.
  """
  def list_agents_for_flyout(nil) do
    do_load_agents(Path.expand("~"))
    |> Enum.filter(&(&1.source == :agents))
    |> Enum.take(15)
  end

  def list_agents_for_flyout(%{path: path}) when is_binary(path) and path != "" do
    do_load_agents(path)
    |> Enum.filter(&(&1.source == :project_agents))
    |> Enum.take(15)
  end

  def list_agents_for_flyout(_), do: list_agents_for_flyout(nil)

  @doc """
  Loads agents for the rail flyout with search and scope filtering.
  scope: "all" | "global" | "project"
  """
  def list_agents_for_flyout_filtered(project, search \\ "", scope \\ "all") do
    project_path =
      case project do
        %{path: p} when is_binary(p) and p != "" -> p
        _ -> Path.expand("~")
      end

    do_load_agents(project_path)
    |> filter_by_scope(scope)
    |> filter_by_search(search)
    |> Enum.take(30)
  end

  def load_agents(socket) do
    project_path = project_path_for(socket)
    agents = do_load_agents(project_path)
    filtered = apply_filters_and_sort(agents, socket.assigns)

    socket
    |> assign(:agents, agents)
    |> assign(:filtered_agents, filtered)
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

  def handle_sort_agents(%{"by" => by}, socket, reload_fn) do
    {:noreply, socket |> assign(:sort_by, by) |> reload_fn.()}
  end

  def handle_filter_scope(%{"scope" => scope}, socket, reload_fn) do
    {:noreply, socket |> assign(:scope_filter, scope) |> reload_fn.()}
  end

  def apply_filters_and_sort(agents, assigns) do
    agents
    |> filter_by_scope(assigns.scope_filter)
    |> filter_by_search(assigns.search_query)
    |> sort_agents(assigns.sort_by)
  end

  defp filter_by_scope(agents, "all"), do: agents

  defp filter_by_scope(agents, "global") do
    Enum.filter(agents, &(&1.source == :agents))
  end

  defp filter_by_scope(agents, "project") do
    Enum.filter(agents, &(&1.source == :project_agents))
  end

  defp filter_by_scope(agents, _), do: agents

  defp filter_by_search(agents, ""), do: agents

  defp filter_by_search(agents, query) do
    q = String.downcase(query)

    Enum.filter(agents, fn agent ->
      String.contains?(String.downcase(agent.slug), q) ||
        String.contains?(String.downcase(agent.name || ""), q) ||
        String.contains?(String.downcase(agent.description || ""), q)
    end)
  end

  defp sort_agents(agents, "name_desc"), do: Enum.sort_by(agents, &display_name/1, :desc)
  defp sort_agents(agents, "size_desc"), do: Enum.sort_by(agents, & &1.size, :desc)
  defp sort_agents(agents, "size_asc"), do: Enum.sort_by(agents, & &1.size)
  defp sort_agents(agents, "recent"), do: Enum.sort_by(agents, & &1.mtime, :desc)
  defp sort_agents(agents, _), do: Enum.sort_by(agents, &display_name/1)

  defp display_name(agent), do: String.downcase(agent.name || agent.slug)

  defp do_load_agents(project_path) do
    global = load_from_dir(Path.expand("~/.claude/agents"), :agents, "~/.claude/agents")
    project = load_from_dir(Path.join(project_path, ".claude/agents"), :project_agents, ".claude/agents")

    (global ++ project)
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
          |> Enum.filter(&(String.ends_with?(&1, ".md") && &1 != "README.md"))
          |> Enum.flat_map(fn filename ->
            path = Path.join(dir, filename)
            slug = String.replace_trailing(filename, ".md", "")

            case File.read(path) do
              {:error, _} ->
                []

              {:ok, content} ->
                stat = File.stat!(path)
                {name, description, model, tools} = parse_frontmatter(content)

                [
                  %AgentDef{
                    id: build_id(source, slug),
                    slug: slug,
                    filename: filename,
                    path: "#{display_prefix}/#{filename}",
                    abs_path: path,
                    source: source,
                    name: name || slug,
                    description: description,
                    model: model,
                    tools: tools,
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

  defp parse_frontmatter(content) do
    case Regex.run(~r/\A---\n(.*?)\n---/s, content) do
      [_, frontmatter] ->
        name = extract_field(frontmatter, "name")
        description = extract_field(frontmatter, "description")
        model = extract_field(frontmatter, "model")
        tools = extract_tools(frontmatter)
        {name, description, model, tools}

      _ ->
        {nil, extract_first_heading(content), nil, []}
    end
  end

  defp extract_field(frontmatter, field) do
    case Regex.run(~r/^#{field}:\s*"?([^"\n]+)"?\s*$/m, frontmatter) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp extract_tools(frontmatter) do
    case Regex.run(~r/^tools:\s*\n((?:\s+-\s*.+\n?)+)/m, frontmatter) do
      [_, block] ->
        block
        |> String.split("\n")
        |> Enum.map(&Regex.replace(~r/^\s*-\s*/, &1, ""))
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        case Regex.run(~r/^tools:\s*\[([^\]]*)\]/m, frontmatter) do
          [_, inline] ->
            inline |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

          _ ->
            []
        end
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

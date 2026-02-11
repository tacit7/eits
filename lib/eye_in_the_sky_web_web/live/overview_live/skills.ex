defmodule EyeInTheSkyWebWeb.OverviewLive.Skills do
  use EyeInTheSkyWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    skills = load_skills()

    socket =
      socket
      |> assign(:page_title, "Skills")
      |> assign(:skills, skills)
      |> assign(:filtered_skills, skills)
      |> assign(:search, "")
      |> assign(:selected_skill, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    filtered =
      if query == "" do
        socket.assigns.skills
      else
        q = String.downcase(query)

        Enum.filter(socket.assigns.skills, fn skill ->
          String.contains?(String.downcase(skill.slug), q) ||
            String.contains?(String.downcase(skill.description), q)
        end)
      end

    {:noreply,
     socket
     |> assign(:search, query)
     |> assign(:filtered_skills, filtered)}
  end

  @impl true
  def handle_event("select_skill", %{"slug" => slug}, socket) do
    selected =
      if socket.assigns.selected_skill && socket.assigns.selected_skill.slug == slug do
        nil
      else
        Enum.find(socket.assigns.skills, &(&1.slug == slug))
      end

    {:noreply, assign(socket, :selected_skill, selected)}
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply, assign(socket, :selected_skill, nil)}
  end

  defp load_skills do
    commands = load_from_commands()
    skills = load_from_skills_dir()

    (commands ++ skills)
    |> Enum.sort_by(& &1.slug)
  end

  # ~/.claude/commands/*.md (legacy slash commands)
  defp load_from_commands do
    commands_dir = Path.expand("~/.claude/commands")

    if File.dir?(commands_dir) do
      commands_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(fn filename ->
        path = Path.join(commands_dir, filename)
        slug = String.replace_trailing(filename, ".md", "")
        content = File.read!(path)

        %{
          slug: slug,
          filename: filename,
          source: :commands,
          description: extract_description(content),
          content: content,
          size: byte_size(content)
        }
      end)
    else
      []
    end
  end

  # ~/.claude/skills/*/SKILL.md (new skills format)
  defp load_from_skills_dir do
    skills_dir = Path.expand("~/.claude/skills")

    if File.dir?(skills_dir) do
      skills_dir
      |> File.ls!()
      |> Enum.filter(fn dir ->
        Path.join([skills_dir, dir, "SKILL.md"]) |> File.exists?()
      end)
      |> Enum.map(fn dir ->
        path = Path.join([skills_dir, dir, "SKILL.md"])
        content = File.read!(path)

        %{
          slug: dir,
          filename: "skills/#{dir}/SKILL.md",
          source: :skills,
          description: extract_description(content),
          content: content,
          size: byte_size(content)
        }
      end)
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

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <EyeInTheSkyWebWeb.Components.OverviewNav.render current_tab={:skills} />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <%= if length(@skills) > 0 do %>
          <!-- Search -->
          <div class="mb-6">
            <form phx-change="search" class="relative">
              <input
                type="text"
                name="search"
                value={@search}
                placeholder="Filter skills..."
                class="input input-bordered input-sm w-full max-w-xs"
                phx-debounce="150"
              />
              <%= if @search != "" do %>
                <span class="text-xs text-base-content/50 ml-2">
                  {@filtered_skills |> length()} of {@skills |> length()}
                </span>
              <% end %>
            </form>
          </div>

          <div class={if @selected_skill, do: "grid grid-cols-1 lg:grid-cols-2 gap-6", else: ""}>
            <!-- Left: skill cards -->
            <div>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <%= for skill <- @filtered_skills do %>
                  <button
                    phx-click="select_skill"
                    phx-value-slug={skill.slug}
                    class={"card bg-base-100 border border-base-300 shadow-sm text-left transition-all hover:border-primary cursor-pointer #{if @selected_skill && @selected_skill.slug == skill.slug, do: "border-primary ring-1 ring-primary"}"}
                  >
                    <div class="card-body p-4">
                      <div class="flex items-center gap-2 mb-2">
                        <svg class="w-4 h-4 text-primary" fill="currentColor" viewBox="0 0 16 16">
                          <path d="M6.122.392a1.75 1.75 0 0 1 1.756 0l5.25 3.045c.54.313.872.89.872 1.514V7.25a.75.75 0 0 1-1.5 0V5.677L7.75 8.432v6.384a1 1 0 0 1-1.502.865L.872 12.563A1.75 1.75 0 0 1 0 11.049V4.951c0-.624.332-1.2.872-1.514ZM7 7.564 11.546 5 7 2.437 2.454 5Z" />
                        </svg>
                        <code class="text-sm font-semibold text-primary">/{skill.slug}</code>
                      </div>
                      <p class="text-sm text-base-content/70 line-clamp-2 mb-3">
                        {skill.description}
                      </p>
                      <div class="flex items-center justify-between text-xs text-base-content/50">
                        <span class={"badge badge-xs " <> if(skill.source == :skills, do: "badge-primary", else: "badge-ghost")}>
                          {if skill.source == :skills, do: "skill", else: "command"}
                        </span>
                        <span>{format_size(skill.size)}</span>
                      </div>
                    </div>
                  </button>
                <% end %>
              </div>
            </div>

            <!-- Right: skill viewer -->
            <%= if @selected_skill do %>
              <div class="sticky top-20">
                <div class="card bg-base-100 border border-base-300 shadow-sm">
                  <div class="card-body p-0">
                    <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 bg-base-200/50">
                      <code class="text-sm font-semibold text-base-content">/{@selected_skill.slug}</code>
                      <button phx-click="close_viewer" class="btn btn-ghost btn-xs btn-circle">
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                      </button>
                    </div>
                    <div class="overflow-auto max-h-[70vh]">
                      <div
                        id={"skill-viewer-#{@selected_skill.slug}"}
                        class="dm-markdown p-4 text-sm text-base-content leading-relaxed"
                        phx-hook="MarkdownMessage"
                        data-raw-body={@selected_skill.content}
                      >
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-12">
            <svg class="mx-auto h-12 w-12 text-base-content/40" fill="currentColor" viewBox="0 0 16 16">
              <path d="M6.122.392a1.75 1.75 0 0 1 1.756 0l5.25 3.045c.54.313.872.89.872 1.514V7.25a.75.75 0 0 1-1.5 0V5.677L7.75 8.432v6.384a1 1 0 0 1-1.502.865L.872 12.563A1.75 1.75 0 0 1 0 11.049V4.951c0-.624.332-1.2.872-1.514ZM7 7.564 11.546 5 7 2.437 2.454 5Z" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-base-content">No skills found</h3>
            <p class="mt-1 text-sm text-base-content/60">
              Add .md files to ~/.claude/commands/ or ~/.claude/skills/ to create skills
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end

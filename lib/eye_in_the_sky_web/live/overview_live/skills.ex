defmodule EyeInTheSkyWeb.OverviewLive.Skills do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Helpers.FileHelpers
  alias EyeInTheSkyWeb.OverviewLive.Skills.Skill

  @impl true
  def mount(_params, _session, socket) do
    skills = if connected?(socket), do: load_skills(), else: []

    socket =
      socket
      |> assign(:page_title, "Skills")
      |> assign(:skills, skills)
      |> assign(:filtered_skills, skills)
      |> assign(:search_query, "")
      |> assign(:selected_skill, nil)
      |> assign(:sidebar_tab, :skills)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
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
     |> assign(:search_query, query)
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
      case File.ls(commands_dir) do
        {:error, _} ->
          []

        {:ok, entries} ->
          entries
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.flat_map(fn filename ->
            path = Path.join(commands_dir, filename)
            slug = String.replace_trailing(filename, ".md", "")

            case File.read(path) do
              {:error, _} ->
                []

              {:ok, content} ->
                [
                  %Skill{
                    slug: slug,
                    filename: filename,
                    source: :commands,
                    description: extract_description(content),
                    content: content,
                    size: byte_size(content)
                  }
                ]
            end
          end)
      end
    else
      []
    end
  end

  # ~/.claude/skills/*/SKILL.md (new skills format)
  defp load_from_skills_dir do
    skills_dir = Path.expand("~/.claude/skills")

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
                [
                  %Skill{
                    slug: dir,
                    filename: "skills/#{dir}/SKILL.md",
                    source: :skills,
                    description: extract_description(content),
                    content: content,
                    size: byte_size(content)
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <%= if @skills != [] do %>
          <!-- Search (mobile only — desktop uses top bar) -->
          <div class="mb-6 md:hidden">
            <form phx-change="search" class="relative">
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Filter skills..."
                class="input input-bordered input-sm w-full max-w-xs text-base min-h-[44px]"
                phx-debounce="150"
              />
              <%= if @search_query != "" do %>
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
                        <.icon name="hero-puzzle-piece" class="w-4 h-4 text-primary" />
                        <code class="text-sm font-semibold text-primary">/{skill.slug}</code>
                      </div>
                      <p class="text-sm text-base-content/70 line-clamp-2 mb-3">
                        {skill.description}
                      </p>
                      <div class="flex items-center justify-between text-xs text-base-content/50">
                        <span class={"badge badge-xs " <> if(skill.source == :skills, do: "badge-primary", else: "badge-ghost")}>
                          {if skill.source == :skills, do: "skill", else: "command"}
                        </span>
                        <span>{FileHelpers.format_size(skill.size)}</span>
                      </div>
                    </div>
                  </button>
                <% end %>
              </div>
            </div>
            
    <!-- Right: skill viewer -->
            <%= if @selected_skill do %>
              <div class="sticky top-[calc(3rem+env(safe-area-inset-top))] md:top-20">
                <div class="card bg-base-100 border border-base-300 shadow-sm">
                  <div class="card-body p-0">
                    <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 bg-base-200/50">
                      <code class="text-sm font-semibold text-base-content">
                        /{@selected_skill.slug}
                      </code>
                      <button
                        phx-click="close_viewer"
                        class="btn btn-ghost btn-xs btn-circle min-h-[44px] min-w-[44px]"
                      >
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
          <.empty_state
            id="overview-skills-empty"
            icon="hero-code-bracket"
            title="No skills found"
            subtitle="Add .md files to ~/.claude/commands/ or ~/.claude/skills/ to create skills"
          />
        <% end %>
      </div>
    </div>
    """
  end
end

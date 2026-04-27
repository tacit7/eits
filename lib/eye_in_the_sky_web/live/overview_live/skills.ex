defmodule EyeInTheSkyWeb.OverviewLive.Skills do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Helpers.FileHelpers
  import EyeInTheSkyWeb.Live.Shared.SkillsHelpers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Skills")
      |> assign(:search_query, "")
      |> assign(:sort_by, "name_asc")
      |> assign(:source_filter, "all")
      |> assign(:skills, [])
      |> assign(:filtered_skills, [])
      |> assign(:selected_skill, nil)
      |> assign(:sidebar_tab, :skills)
      |> assign(:sidebar_project, nil)

    socket = if connected?(socket), do: load_skills(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_skills/1)

  @impl true
  def handle_event("sort_skills", params, socket),
    do: handle_sort_skills(params, socket, &load_skills/1)

  @impl true
  def handle_event("filter_source", params, socket),
    do: handle_filter_source(params, socket, &load_skills/1)

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

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Mobile-only controls bar --%>
    <div class="md:hidden flex flex-wrap items-center gap-2 px-4 pt-3 pb-1">
      <form phx-change="sort_skills">
        <label for="skills-sort-mobile" class="sr-only">Sort skills</label>
        <select
          id="skills-sort-mobile"
          name="by"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="name_asc" selected={@sort_by == "name_asc"}>Name A–Z</option>
          <option value="name_desc" selected={@sort_by == "name_desc"}>Name Z–A</option>
          <option value="recent" selected={@sort_by == "recent"}>Recent</option>
          <option value="size_desc" selected={@sort_by == "size_desc"}>Largest</option>
          <option value="size_asc" selected={@sort_by == "size_asc"}>Smallest</option>
        </select>
      </form>
      <form phx-change="filter_source">
        <label for="skills-source-mobile" class="sr-only">Filter by source</label>
        <select
          id="skills-source-mobile"
          name="filter"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="all" selected={@source_filter == "all"}>All Sources</option>
          <option value="skills" selected={@source_filter == "skills"}>Skills</option>
          <option value="commands" selected={@source_filter == "commands"}>Commands</option>
        </select>
      </form>
    </div>

    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <%!-- Count row --%>
        <div class="mb-3">
          <span class="text-mini font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            {length(@filtered_skills)} skills
          </span>
        </div>

        <%= if @filtered_skills != [] do %>
          <div class={if @selected_skill, do: "grid grid-cols-1 md:grid-cols-2 gap-6", else: ""}>
            <%!-- Left: list --%>
            <div>
              <div class="divide-y divide-base-content/5 bg-base-100 rounded-xl shadow-sm px-5">
                <%= for skill <- @filtered_skills do %>
                  <div class="py-1 relative">
                    <div class="collapse overflow-visible">
                      <input type="checkbox" class="min-h-0 p-0" />
                      <%!-- Row: fires select_skill for desktop side panel --%>
                      <div
                        class="collapse-title py-3 px-0 min-h-0 flex flex-col gap-1 cursor-pointer"
                        phx-click="select_skill"
                        phx-value-slug={skill.slug}
                      >
                        <div class="flex items-center gap-2">
                          <.icon
                            name="hero-puzzle-piece"
                            class={"size-3.5 flex-shrink-0 " <>
                              if(@selected_skill && @selected_skill.slug == skill.slug,
                                do: "text-primary",
                                else: "text-base-content/40"
                              )}
                          />
                          <code class={"text-sm font-semibold truncate " <>
                            if(@selected_skill && @selected_skill.slug == skill.slug,
                              do: "text-primary",
                              else: "text-base-content/85"
                            )}>
                            /{skill.slug}
                          </code>
                        </div>
                        <div class="flex items-center gap-1.5 text-mini text-base-content/40 pl-5">
                          <span class={"inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium " <>
                            if(skill.source == :skills,
                              do: "bg-primary/10 text-primary/70",
                              else: "bg-base-content/5 text-base-content/40"
                            )}>
                            {if skill.source == :skills, do: "skill", else: "command"}
                          </span>
                          <span class="text-base-content/20">&middot;</span>
                          <span class="tabular-nums">{FileHelpers.format_size(skill.size)}</span>
                          <span class="text-base-content/20">&middot;</span>
                          <span class="truncate max-w-xs">{skill.description}</span>
                        </div>
                      </div>
                      <%!-- Mobile inline viewer: hidden on desktop --%>
                      <div class="collapse-content md:hidden px-0 pb-3">
                        <div
                          id={"skill-mobile-#{skill.slug}"}
                          class="dm-markdown text-sm text-base-content leading-relaxed"
                          phx-hook="MarkdownMessage"
                          data-raw-body={skill.content}
                        >
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Right: desktop side panel --%>
            <%= if @selected_skill do %>
              <div class="hidden md:block sticky top-[calc(3rem+env(safe-area-inset-top))] md:top-20">
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
                        <.icon name="hero-x-mark" class="size-4" />
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
            title={if @search_query != "" || @source_filter != "all",
              do: "No skills found",
              else: "No skills yet"}
            subtitle={
              if @search_query != "" || @source_filter != "all",
                do: "Try adjusting your search or filter",
                else: "Add .md files to ~/.claude/commands/ or ~/.claude/skills/ to create skills"
            }
          />
        <% end %>
      </div>
    </div>
    """
  end
end

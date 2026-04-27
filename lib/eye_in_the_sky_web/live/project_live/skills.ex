defmodule EyeInTheSkyWeb.ProjectLive.Skills do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Helpers.FileHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Live.Shared.SkillsHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :skills,
        page_title_prefix: "Skills"
      )
      |> assign(:search_query, "")
      |> assign(:sort_by, "name_asc")
      |> assign(:type_filter, "all")
      |> assign(:scope_filter, "all")
      |> assign(:skills, [])
      |> assign(:filtered_skills, [])
      |> assign(:selected_skill, nil)
      |> assign(:detail_tab, :preview)

    socket = if connected?(socket), do: load_skills(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_skills/1)

  @impl true
  def handle_event("sort_skills", params, socket),
    do: handle_sort_skills(params, socket, &load_skills/1)

  @impl true
  def handle_event("filter_type", params, socket),
    do: handle_filter_type(params, socket, &load_skills/1)

  @impl true
  def handle_event("filter_scope", params, socket),
    do: handle_filter_scope(params, socket, &load_skills/1)

  @impl true
  def handle_event("select_skill", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_skill && socket.assigns.selected_skill.id == id do
        nil
      else
        Enum.find(socket.assigns.skills, &(&1.id == id))
      end

    {:noreply, socket |> assign(:selected_skill, selected) |> assign(:detail_tab, :preview)}
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply, assign(socket, :selected_skill, nil)}
  end

  @impl true
  def handle_event("set_detail_tab", %{"tab" => "preview"}, socket),
    do: {:noreply, assign(socket, :detail_tab, :preview)}

  def handle_event("set_detail_tab", %{"tab" => "raw"}, socket),
    do: {:noreply, assign(socket, :detail_tab, :raw)}

  def handle_event("set_detail_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Mobile-only controls --%>
    <div class="md:hidden flex flex-wrap items-center gap-2 px-4 pt-3 pb-1">
      <form phx-change="sort_skills">
        <label for="proj-skills-sort-mobile" class="sr-only">Sort skills</label>
        <select
          id="proj-skills-sort-mobile"
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
      <form phx-change="filter_type">
        <label for="proj-skills-type-mobile" class="sr-only">Filter by type</label>
        <select
          id="proj-skills-type-mobile"
          name="filter"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="all" selected={@type_filter == "all"}>All Types</option>
          <option value="skills" selected={@type_filter == "skills"}>Skills</option>
          <option value="commands" selected={@type_filter == "commands"}>Commands</option>
        </select>
      </form>
      <form phx-change="filter_scope">
        <label for="proj-skills-scope-mobile" class="sr-only">Filter by source</label>
        <select
          id="proj-skills-scope-mobile"
          name="scope"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="all" selected={@scope_filter == "all"}>All Sources</option>
          <option value="global" selected={@scope_filter == "global"}>Global</option>
          <option value="project" selected={@scope_filter == "project"}>Project</option>
        </select>
      </form>
    </div>

    <div class={[
      "flex overflow-hidden",
      @selected_skill && "flex-1"
    ]}>
      <%!-- List panel --%>
      <div class={[
        "overflow-y-auto px-4 sm:px-6 py-6",
        if(@selected_skill, do: "w-[440px] flex-shrink-0 border-r border-base-content/8", else: "w-full max-w-3xl mx-auto")
      ]}>
        <div class="mb-3">
          <span class="text-mini font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            {length(@filtered_skills)} skills
          </span>
        </div>

        <%= if @filtered_skills != [] do %>
          <div class="divide-y divide-base-content/5">
            <%= for skill <- @filtered_skills do %>
              <% selected? = @selected_skill && @selected_skill.id == skill.id %>
              <div class={["py-0.5", selected? && "relative"]}>
                <div class="collapse overflow-visible">
                  <input
                    type="checkbox"
                    class="min-h-0 p-0"
                    phx-click="select_skill"
                    phx-value-id={skill.id}
                  />
                  <div class={[
                    "collapse-title py-2.5 px-3 min-h-0 flex flex-col gap-0.5 cursor-pointer rounded-lg",
                    if(selected?, do: "bg-primary/5 border-l-2 border-primary", else: "hover:bg-base-content/4")
                  ]}>
                    <div class="flex items-center gap-2">
                      <.icon
                        name="hero-puzzle-piece"
                        class={"size-3.5 flex-shrink-0 " <>
                          if(selected?, do: "text-primary", else: "text-base-content/35")}
                      />
                      <code class={"text-sm font-semibold " <>
                        if(selected?, do: "text-primary", else: "text-base-content/85")}>
                        /{skill.slug}
                      </code>
                    </div>
                    <p class="text-xs text-base-content/55 leading-snug pl-5 line-clamp-2">
                      {skill.description}
                    </p>
                    <div class="flex items-center gap-1.5 pl-5 mt-0.5">
                      <span class={"inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium " <>
                        source_badge_class(skill.source)}>
                        {source_label(skill.source)}
                      </span>
                      <span class="text-base-content/20 text-xs">&middot;</span>
                      <span class="text-[10px] text-base-content/40 tabular-nums">{FileHelpers.format_size(skill.size)}</span>
                      <span class="text-base-content/20 text-xs">&middot;</span>
                      <span class="text-[10px] text-base-content/35 font-mono truncate">{skill.path}</span>
                    </div>
                  </div>
                  <div class="collapse-content md:hidden px-3 pb-3">
                    <div
                      id={"proj-skill-mobile-#{skill.id}"}
                      class="dm-markdown text-sm text-base-content leading-relaxed mt-2"
                      phx-hook="MarkdownMessage"
                      data-raw-body={skill.content}
                    >
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="proj-skills-empty"
            icon="hero-code-bracket"
            title={if @search_query != "" || @type_filter != "all" || @scope_filter != "all",
              do: "No skills found",
              else: "No skills yet"}
            subtitle={
              if @search_query != "" || @type_filter != "all" || @scope_filter != "all",
                do: "Try adjusting your search or filters",
                else: "Add .md files to .claude/commands/ or .claude/skills/ in your project"
            }
          />
        <% end %>
      </div>

      <%!-- Desktop detail panel --%>
      <%= if @selected_skill do %>
        <div class="hidden md:flex flex-col flex-1 overflow-hidden">
          <div class="flex-shrink-0 px-6 pt-5 pb-4 border-b border-base-content/8">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <code class="text-base font-semibold text-base-content">/{@selected_skill.slug}</code>
                  <span class={"inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium " <>
                    source_badge_class(@selected_skill.source)}>
                    {source_label(@selected_skill.source)}
                  </span>
                </div>
                <p class="text-xs text-base-content/45 font-mono truncate">{@selected_skill.path}</p>
                <p class="text-sm text-base-content/60 mt-1.5 leading-snug">{@selected_skill.description}</p>
              </div>
              <button
                phx-click="close_viewer"
                class="btn btn-ghost btn-xs btn-circle flex-shrink-0 min-h-[36px] min-w-[36px]"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
            <div class="flex items-center gap-1 mt-3">
              <button
                phx-click="set_detail_tab"
                phx-value-tab="preview"
                class={"px-3 py-1 rounded text-xs font-medium " <>
                  if(@detail_tab == :preview,
                    do: "bg-base-content/8 text-base-content",
                    else: "text-base-content/50 hover:text-base-content")}
              >
                Preview
              </button>
              <button
                phx-click="set_detail_tab"
                phx-value-tab="raw"
                class={"px-3 py-1 rounded text-xs font-medium " <>
                  if(@detail_tab == :raw,
                    do: "bg-base-content/8 text-base-content",
                    else: "text-base-content/50 hover:text-base-content")}
              >
                Raw
              </button>
              <span class="ml-auto text-[10px] text-base-content/35 tabular-nums">
                {FileHelpers.format_size(@selected_skill.size)}
              </span>
            </div>
          </div>
          <div class="flex-1 overflow-y-auto">
            <%= if @detail_tab == :preview do %>
              <div
                id={"proj-skill-viewer-#{@selected_skill.id}"}
                class="dm-markdown px-6 py-4 text-sm text-base-content leading-relaxed"
                phx-hook="MarkdownMessage"
                data-raw-body={@selected_skill.content}
              >
              </div>
            <% else %>
              <pre class="px-6 py-4 text-xs font-mono text-base-content/75 whitespace-pre-wrap break-words leading-relaxed">{@selected_skill.content}</pre>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp source_badge_class(:skills), do: "bg-primary/10 text-primary/70"
  defp source_badge_class(:project_skills), do: "bg-secondary/10 text-secondary/70"
  defp source_badge_class(:project_commands), do: "bg-secondary/10 text-secondary/70"
  defp source_badge_class(_), do: "bg-base-content/5 text-base-content/50"

  defp source_label(:skills), do: "skill"
  defp source_label(:commands), do: "command"
  defp source_label(:project_skills), do: "project skill"
  defp source_label(:project_commands), do: "project cmd"
end

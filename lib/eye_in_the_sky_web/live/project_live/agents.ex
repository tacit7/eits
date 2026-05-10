defmodule EyeInTheSkyWeb.ProjectLive.Agents do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Helpers.FileHelpers
  alias EyeInTheSkyWeb.Helpers.ViewHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  alias EyeInTheSky.AgentManager
  alias EyeInTheSky.Agents.AgentCreationHelpers
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Live.Shared.AgentsHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket =
      socket
      |> mount_project(params, sidebar_tab: :agents, page_title_prefix: "Agents")
      |> assign(:search_query, "")
      |> assign(:sort_by, "name_asc")
      |> assign(:scope_filter, "all")
      |> assign(:agents, [])
      |> assign(:filtered_agents, [])
      |> assign(:selected_agent, nil)
      |> assign(:detail_tab, :preview)
      |> assign(:show_new_agent_form, false)
      |> assign(:new_agent_name, "")
      |> assign(:new_agent_description, "")

    socket = if connected?(socket), do: load_agents(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_agents/1)

  @impl true
  def handle_event("sort_agents", params, socket),
    do: handle_sort_agents(params, socket, &load_agents/1)

  @impl true
  def handle_event("filter_scope", params, socket),
    do: handle_filter_scope(params, socket, &load_agents/1)

  @impl true
  def handle_event("select_agent", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_agent && socket.assigns.selected_agent.id == id do
        nil
      else
        Enum.find(socket.assigns.agents, &(&1.id == id))
      end

    {:noreply, socket |> assign(:selected_agent, selected) |> assign(:detail_tab, :preview)}
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply, assign(socket, :selected_agent, nil)}
  end

  @impl true
  def handle_event("open_file", _params, socket) do
    case socket.assigns.selected_agent do
      %{abs_path: path} when is_binary(path) ->
        if open_path_allowed?(path, socket), do: ViewHelpers.open_in_system(path)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_detail_tab", %{"tab" => "preview"}, socket),
    do: {:noreply, assign(socket, :detail_tab, :preview)}

  def handle_event("set_detail_tab", %{"tab" => "raw"}, socket),
    do: {:noreply, assign(socket, :detail_tab, :raw)}

  def handle_event("set_detail_tab", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_new_agent_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_agent_form, !socket.assigns.show_new_agent_form)
     |> assign(:new_agent_name, "")
     |> assign(:new_agent_description, "")}
  end

  @impl true
  def handle_event("update_agent_form", params, socket) do
    {:noreply,
     socket
     |> assign(:new_agent_name, params["agent_name"] || "")
     |> assign(:new_agent_description, params["agent_description"] || "")}
  end

  @impl true
  def handle_event("create_agent", params, socket) do
    agent_name = String.trim(params["agent_name"] || "")
    description = String.trim(params["agent_description"] || "")

    cond do
      agent_name == "" ->
        {:noreply, put_flash(socket, :error, "Agent name is required")}

      description == "" ->
        {:noreply, put_flash(socket, :error, "Description is required")}

      true ->
        create_new_agent(agent_name, description, socket)
    end
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="md:hidden flex flex-wrap items-center gap-2 px-4 pt-3 pb-1">
      <form phx-change="sort_agents">
        <label for="proj-agents-sort-mobile" class="sr-only">Sort agents</label>
        <select
          id="proj-agents-sort-mobile"
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
      <form phx-change="filter_scope">
        <label for="proj-agents-scope-mobile" class="sr-only">Filter by source</label>
        <select
          id="proj-agents-scope-mobile"
          name="scope"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="all" selected={@scope_filter == "all"}>All Sources</option>
          <option value="global" selected={@scope_filter == "global"}>Global</option>
          <option value="project" selected={@scope_filter == "project"}>Project</option>
        </select>
      </form>
    </div>

    <div class={["flex overflow-hidden", @selected_agent && "flex-1"]}>
      <div
        class={[
          "overflow-y-auto px-4 sm:px-6 py-6",
          if(@selected_agent,
            do: "w-[440px] flex-shrink-0 border-r border-base-content/8",
            else: "w-full max-w-3xl mx-auto"
          )
        ]}
        style="scrollbar-width: none;"
      >
        <div class="mb-3 flex items-center gap-3">
          <span class="text-mini font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            {length(@filtered_agents)} agents
          </span>
          <form phx-change="search" class="ml-auto">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search agents..."
              data-vim-search
              class="input input-xs bg-base-200/50 border-base-content/8 text-base-content/70 placeholder:text-base-content/30 min-h-[28px] text-xs w-40 focus:w-56 transition-all"
            />
          </form>
          <button
            phx-click="toggle_new_agent_form"
            title="Create new agent"
            class="btn btn-ghost btn-xs gap-1.5 min-h-[28px] h-7 text-xs text-base-content/60 hover:text-primary hover:bg-primary/5"
          >
            <.icon name="hero-plus-mini" class="size-3.5" />
            New
          </button>
        </div>

        <%= if @filtered_agents != [] do %>
          <div class="divide-y divide-base-content/5" data-vim-list>
            <%= for agent <- @filtered_agents do %>
              <% selected? = @selected_agent && @selected_agent.id == agent.id %>
              <div class="py-0.5">
                <div
                  class={[
                    "py-2.5 px-3 flex flex-col gap-0.5 cursor-pointer rounded-lg transition-colors",
                    "[&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50",
                    if(selected?,
                      do: "bg-primary/5 border-l-2 border-primary",
                      else: "hover:bg-base-200/40"
                    )
                  ]}
                  phx-click="select_agent"
                  phx-value-id={agent.id}
                  data-vim-list-item
                  role="button"
                >
                  <div class="flex items-center gap-2">
                    <.custom_icon
                      name="lucide-robot"
                      class={"size-3.5 flex-shrink-0 " <> if(selected?, do: "text-primary", else: "text-base-content/35")}
                    />
                    <code class={"text-sm font-semibold " <> if(selected?, do: "text-primary", else: "text-base-content/85")}>
                      {agent.name}
                    </code>
                  </div>
                  <p class="text-xs text-base-content/55 leading-snug pl-5 line-clamp-2">
                    {agent.description}
                  </p>
                  <div class="flex items-center gap-1.5 pl-5 mt-0.5">
                    <span class={"inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium " <> source_badge_class(agent.source)}>
                      {source_label(agent.source)}
                    </span>
                    <span class="text-base-content/20 text-xs">&middot;</span>
                    <span class="text-[10px] text-base-content/40 tabular-nums">
                      {FileHelpers.format_size(agent.size)}
                    </span>
                    <%= if agent.model do %>
                      <span class="text-base-content/20 text-xs">&middot;</span>
                      <span class="text-[10px] text-base-content/35 font-mono truncate">
                        {agent.model}
                      </span>
                    <% end %>
                    <span class="text-base-content/20 text-xs">&middot;</span>
                    <span class="text-[10px] text-base-content/35 font-mono truncate">
                      {agent.path}
                    </span>
                  </div>
                </div>
                <%= if selected? do %>
                  <div class="md:hidden px-3 pb-3">
                    <div
                      id={"proj-agent-mobile-#{agent.id}"}
                      class="dm-markdown text-sm text-base-content leading-relaxed mt-2"
                      phx-hook="MarkdownMessage"
                      data-raw-body={agent.content}
                    >
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="proj-agents-empty"
            icon="hero-cpu-chip"
            title={
              if @search_query != "" || @scope_filter != "all",
                do: "No agents found",
                else: "No agents yet"
            }
            subtitle={
              if @search_query != "" || @scope_filter != "all",
                do: "Try adjusting your search or filters",
                else: "Add .md files to .claude/agents/ in your project"
            }
          />
        <% end %>
      </div>

      <%= if @selected_agent do %>
        <div class="hidden md:flex flex-col flex-1 overflow-hidden">
          <div class="flex-shrink-0 px-6 pt-5 pb-4 border-b border-base-content/8">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <code class="text-base font-semibold text-base-content">
                    {@selected_agent.name}
                  </code>
                  <span class={"inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium " <> source_badge_class(@selected_agent.source)}>
                    {source_label(@selected_agent.source)}
                  </span>
                  <%= if @selected_agent.model do %>
                    <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-base-content/5 text-base-content/50">
                      {@selected_agent.model}
                    </span>
                  <% end %>
                </div>
                <p class="text-xs text-base-content/45 font-mono truncate">{@selected_agent.path}</p>
                <p class="text-sm text-base-content/60 mt-1.5 leading-snug">
                  {@selected_agent.description}
                </p>
                <%= if @selected_agent.tools != [] do %>
                  <div class="flex flex-wrap gap-1 mt-2">
                    <%= for tool <- @selected_agent.tools do %>
                      <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-mono bg-base-content/5 text-base-content/50">
                        {tool}
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
              <div class="flex items-center gap-1 flex-shrink-0">
                <button
                  phx-click="open_file"
                  title="Open in editor"
                  class="btn btn-ghost btn-xs btn-circle min-h-[36px] min-w-[36px]"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                </button>
                <button
                  phx-click="close_viewer"
                  title="Close"
                  class="btn btn-ghost btn-xs btn-circle min-h-[36px] min-w-[36px]"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </div>
            <div class="flex items-center gap-1 mt-3">
              <button
                phx-click="set_detail_tab"
                phx-value-tab="preview"
                class={"px-3 py-1 rounded text-xs font-medium " <>
                  if(@detail_tab == :preview, do: "bg-base-content/8 text-base-content", else: "text-base-content/50 hover:text-base-content")}
              >
                Preview
              </button>
              <button
                phx-click="set_detail_tab"
                phx-value-tab="raw"
                class={"px-3 py-1 rounded text-xs font-medium " <>
                  if(@detail_tab == :raw, do: "bg-base-content/8 text-base-content", else: "text-base-content/50 hover:text-base-content")}
              >
                Raw
              </button>
              <span class="ml-auto text-[10px] text-base-content/35 tabular-nums">
                {FileHelpers.format_size(@selected_agent.size)}
              </span>
            </div>
          </div>
          <div class="flex-1 overflow-y-auto">
            <%= if @detail_tab == :preview do %>
              <div
                id={"proj-agent-viewer-#{@selected_agent.id}"}
                class="dm-markdown px-6 py-4 text-sm text-base-content leading-relaxed"
                phx-hook="MarkdownMessage"
                data-raw-body={@selected_agent.content}
              >
              </div>
            <% else %>
              <pre class="px-6 py-4 text-xs font-mono text-base-content/75 whitespace-pre-wrap break-words leading-relaxed">{@selected_agent.content}</pre>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>

    <!-- New Agent Modal -->
    <%= if @show_new_agent_form do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" phx-click="toggle_new_agent_form">
        <div
          class="bg-base-100 border border-base-content/10 rounded-lg shadow-xl w-96 p-6 flex flex-col gap-4"
          phx-click="JS.stop_propagation()"
        >
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold text-base-content">Create New Agent</h2>
            <button
              type="button"
              phx-click="toggle_new_agent_form"
              class="size-6 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <form phx-submit="create_agent" class="flex flex-col gap-3">
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Agent Name</label>
              <input
                type="text"
                name="agent_name"
                value={@new_agent_name}
                placeholder="e.g., Code Review Agent"
                autofocus
                required
                phx-change="update_agent_form"
                class="input input-bordered w-full text-base focus:outline-none focus:border-primary/40"
              />
            </div>

            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Description</label>
              <textarea
                name="agent_description"
                value={@new_agent_description}
                placeholder="What should this agent do?"
                rows="4"
                required
                phx-change="update_agent_form"
                class="textarea textarea-bordered w-full text-base focus:outline-none focus:border-primary/40 resize-none"
              ></textarea>
            </div>

            <div class="flex gap-2 mt-2">
              <button
                type="button"
                phx-click="toggle_new_agent_form"
                class="btn btn-ghost flex-1"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="btn btn-primary flex-1"
                disabled={@new_agent_name == "" or @new_agent_description == ""}
              >
                Create Agent
              </button>
            </div>
          </form>
        </div>
      </div>
    <% end %>
    """
  end

  defp source_badge_class(:agents), do: "bg-primary/10 text-primary/70"
  defp source_badge_class(:project_agents), do: "bg-secondary/10 text-secondary/70"
  defp source_badge_class(_), do: "bg-base-content/5 text-base-content/50"

  defp source_label(:agents), do: "global"
  defp source_label(:project_agents), do: "project"
  defp source_label(_), do: "unknown"

  defp open_path_allowed?(path, socket) do
    user_dir = Path.expand("~/.claude/agents")

    project_dir =
      case socket.assigns[:project] do
        %{path: p} when is_binary(p) and p != "" -> Path.join(p, ".claude/agents")
        _ -> nil
      end

    File.exists?(path) &&
      (String.starts_with?(path, user_dir) ||
         (not is_nil(project_dir) && String.starts_with?(path, project_dir)))
  end

  defp create_new_agent(agent_name, description, socket) do
    project = socket.assigns.project
    project_id = socket.assigns.project_id

    opts =
      AgentCreationHelpers.build_opts(%{},
        project_path: project.path,
        description: agent_name,
        instructions: description
      )

    opts =
      opts
      |> Keyword.put(:project_id, project_id)
      |> Keyword.put(:name, agent_name)

    case AgentManager.create_agent(opts) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:show_new_agent_form, false)
         |> put_flash(:info, "Agent created successfully: #{agent_name}")
         |> load_agents()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create agent: #{inspect(reason)}")}
    end
  end
end

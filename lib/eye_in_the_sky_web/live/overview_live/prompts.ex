defmodule EyeInTheSkyWeb.OverviewLive.Prompts do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Live.Shared.PromptsHelpers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Prompts")
      |> assign(:search_query, "")
      |> assign(:sort_by, "recent")
      |> assign(:scope_filter, "all")
      |> assign(:prompts, [])
      |> assign(:filtered_prompts, [])
      |> assign(:selected_prompt, nil)
      |> assign(:detail_tab, :preview)
      |> assign(:sidebar_tab, :prompts)
      |> assign(:sidebar_project, nil)

    socket = if connected?(socket), do: load_prompts(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    selected = Enum.find(socket.assigns.prompts, &(Integer.to_string(&1.id) == id))
    {:noreply, assign(socket, :selected_prompt, selected)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_prompts/1)

  @impl true
  def handle_event("sort_prompts", params, socket),
    do: handle_sort_prompts(params, socket, &load_prompts/1)

  @impl true
  def handle_event("filter_scope", params, socket),
    do: handle_filter_scope(params, socket, &load_prompts/1)

  @impl true
  def handle_event("select_prompt", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_prompt && socket.assigns.selected_prompt.id == String.to_integer(id) do
        nil
      else
        Enum.find(socket.assigns.prompts, &(Integer.to_string(&1.id) == id))
      end

    {:noreply, socket |> assign(:selected_prompt, selected) |> assign(:detail_tab, :preview)}
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply, assign(socket, :selected_prompt, nil)}
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
      <form phx-change="sort_prompts">
        <label for="global-prompts-sort-mobile" class="sr-only">Sort prompts</label>
        <select
          id="global-prompts-sort-mobile"
          name="by"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="name_asc" selected={@sort_by == "name_asc"}>Name A–Z</option>
          <option value="name_desc" selected={@sort_by == "name_desc"}>Name Z–A</option>
          <option value="recent" selected={@sort_by == "recent"}>Recent</option>
        </select>
      </form>
      <form phx-change="filter_scope">
        <label for="global-prompts-scope-mobile" class="sr-only">Filter by scope</label>
        <select
          id="global-prompts-scope-mobile"
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
      @selected_prompt && "flex-1"
    ]}>
      <%!-- List panel --%>
      <div class={[
        "overflow-y-auto px-4 sm:px-6 py-6",
        if(@selected_prompt,
          do: "w-[440px] flex-shrink-0 border-r border-base-content/8",
          else: "w-full max-w-3xl mx-auto"
        )
      ]}>
        <div class="mb-3">
          <span class="text-mini font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            {length(@filtered_prompts)} prompts
          </span>
        </div>

        <%!-- Search bar --%>
        <div class="mb-4">
          <form phx-change="search">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search prompts..."
              class="input input-sm input-bordered w-full bg-base-100 text-base-content placeholder-base-content/40"
            />
          </form>
        </div>

        <%= if @filtered_prompts != [] do %>
          <div class="divide-y divide-base-content/5">
            <%= for prompt <- @filtered_prompts do %>
              <% selected? = @selected_prompt && @selected_prompt.id == prompt.id %>
              <div class={["py-0.5", selected? && "relative"]}>
                <div class="collapse overflow-visible">
                  <input
                    type="checkbox"
                    class="min-h-0 p-0"
                    phx-click="select_prompt"
                    phx-value-id={prompt.id}
                  />
                  <div class={[
                    "collapse-title py-2.5 px-3 min-h-0 flex flex-col gap-0.5 cursor-pointer rounded-lg",
                    if(selected?,
                      do: "bg-primary/5 border-l-2 border-primary",
                      else: "hover:bg-base-content/4"
                    )
                  ]}>
                    <div class="flex items-center gap-2">
                      <.icon
                        name="hero-chat-bubble-left-right"
                        class={"size-3.5 flex-shrink-0 " <>
                          if(selected?, do: "text-primary", else: "text-base-content/35")}
                      />
                      <code class={"text-sm font-semibold " <>
                        if(selected?, do: "text-primary", else: "text-base-content/85")}>
                        /{prompt.slug}
                      </code>
                    </div>
                    <p class="text-xs text-base-content/55 leading-snug pl-5 line-clamp-2">
                      {prompt.description || "No description"}
                    </p>
                    <div class="flex items-center gap-1.5 pl-5 mt-0.5">
                      <span class={[
                        "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium",
                        if(is_nil(prompt.project_id),
                          do: "bg-primary/10 text-primary/70",
                          else: "bg-secondary/10 text-secondary/70"
                        )
                      ]}>
                        {if is_nil(prompt.project_id), do: "global", else: "project"}
                      </span>
                      <span class="text-base-content/20 text-xs">&middot;</span>
                      <span class="text-[10px] text-base-content/35 font-mono">
                        v{prompt.version}
                      </span>
                    </div>
                  </div>
                  <div class="collapse-content md:hidden px-3 pb-3">
                    <div
                      id={"global-prompt-mobile-#{prompt.id}"}
                      class="dm-markdown text-sm text-base-content leading-relaxed mt-2"
                      phx-hook="MarkdownMessage"
                      data-raw-body={prompt.prompt_text}
                    >
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="global-prompts-empty"
            icon="hero-chat-bubble-left-right"
            title={
              if @search_query != "" || @scope_filter != "all",
                do: "No prompts found",
                else: "No prompts yet"
            }
            subtitle={
              if @search_query != "" || @scope_filter != "all",
                do: "Try adjusting your search or filters",
                else: "Create prompts to use with your agents"
            }
          />
        <% end %>
      </div>

      <%!-- Desktop detail panel --%>
      <%= if @selected_prompt do %>
        <div class="hidden md:flex flex-col flex-1 overflow-hidden">
          <div class="flex-shrink-0 px-6 pt-5 pb-4 border-b border-base-content/8">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <code class="text-base font-semibold text-base-content">
                    /{@selected_prompt.slug}
                  </code>
                  <span class={[
                    "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium",
                    if(is_nil(@selected_prompt.project_id),
                      do: "bg-primary/10 text-primary/70",
                      else: "bg-secondary/10 text-secondary/70"
                    )
                  ]}>
                    {if is_nil(@selected_prompt.project_id), do: "global", else: "project"}
                  </span>
                </div>
                <p class="text-sm text-base-content/60 mt-1.5 leading-snug">
                  {@selected_prompt.description || "No description"}
                </p>
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
                v{@selected_prompt.version}
              </span>
            </div>
          </div>
          <div class="flex-1 overflow-y-auto">
            <%= if @detail_tab == :preview do %>
              <div
                id={"global-prompt-viewer-#{@selected_prompt.id}"}
                class="dm-markdown px-6 py-4 text-sm text-base-content leading-relaxed"
                phx-hook="MarkdownMessage"
                data-raw-body={@selected_prompt.prompt_text}
              >
              </div>
            <% else %>
              <pre class="px-6 py-4 text-xs font-mono text-base-content/75 whitespace-pre-wrap break-words leading-relaxed">{@selected_prompt.prompt_text}</pre>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

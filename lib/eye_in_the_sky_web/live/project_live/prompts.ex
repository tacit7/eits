defmodule EyeInTheSkyWeb.ProjectLive.Prompts do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Prompts
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket =
      socket
      |> mount_project(params, sidebar_tab: :prompts, page_title_prefix: "Prompts")
      |> assign(:search_query, "")
      |> assign(:show_all, false)
      |> assign(:prompts, [])
      |> assign(:selected_prompt, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"show_all" => "true"} = _params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, true)
      |> then(fn s -> if connected?(s), do: load_prompts(s), else: s end)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, false)
      |> then(fn s -> if connected?(s), do: load_prompts(s), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> load_prompts()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_prompt", %{"uuid" => uuid}, socket) do
    selected = Enum.find(socket.assigns.prompts, &(&1.uuid == uuid))
    {:noreply, assign(socket, :selected_prompt, selected)}
  end

  defp load_prompts(socket) do
    show_all = Map.get(socket.assigns, :show_all, false)
    query = socket.assigns.search_query

    prompts =
      if show_all do
        if String.trim(query) != "" do
          Prompts.search_prompts(query)
        else
          Prompts.list_prompts()
        end
      else
        project_id = socket.assigns.project_id

        if String.trim(query) != "" do
          Prompts.search_prompts(query, project_id)
        else
          Prompts.list_prompts(project_id: project_id)
        end
      end

    assign(socket, :prompts, prompts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Mobile-only search --%>
    <div class="md:hidden flex items-center gap-2 px-4 pt-3 pb-1">
      <form phx-change="search" class="flex-1">
        <input
          type="text"
          name="query"
          value={@search_query}
          placeholder="Search prompts..."
          class="input input-xs bg-base-200/50 border-base-content/8 text-base-content/70 placeholder:text-base-content/30 min-h-[44px] text-xs w-full"
        />
      </form>
    </div>

    <div class={["flex overflow-hidden", @selected_prompt && "flex-1"]}>
      <%!-- List panel --%>
      <div
        class={[
          "overflow-y-auto px-4 sm:px-6 py-6",
          if(@selected_prompt,
            do: "w-[440px] flex-shrink-0 border-r border-base-content/8",
            else: "w-full max-w-3xl mx-auto"
          )
        ]}
        style="scrollbar-width: none;"
      >
        <div class="mb-3 flex items-center gap-3">
          <span class="text-mini font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            {length(@prompts)} prompts
          </span>
          <form phx-change="search" class="ml-auto">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search prompts..."
              data-vim-search
              class="input input-xs bg-base-200/50 border-base-content/8 text-base-content/70 placeholder:text-base-content/30 min-h-[28px] text-xs w-40 focus:w-56 transition-all hidden md:block"
            />
          </form>
        </div>

        <%= if @prompts != [] do %>
          <div class="divide-y divide-base-content/5" data-vim-list>
            <%= for prompt <- @prompts do %>
              <% selected? = @selected_prompt && @selected_prompt.uuid == prompt.uuid %>
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
                  phx-click="select_prompt"
                  phx-value-uuid={prompt.uuid}
                  data-vim-list-item
                  role="button"
                >
                  <div class="flex items-center gap-2">
                    <.icon
                      name="hero-chat-bubble-left-right"
                      class={"size-3.5 flex-shrink-0 " <> if(selected?, do: "text-primary", else: "text-base-content/35")}
                    />
                    <span class={"text-sm font-semibold " <> if(selected?, do: "text-primary", else: "text-base-content/85")}>
                      {prompt.name}
                    </span>
                    <code class="text-[10px] font-mono text-base-content/40 bg-base-content/5 px-1.5 py-0.5 rounded">
                      {prompt.slug}
                    </code>
                    <%= if !prompt.active do %>
                      <span class="badge badge-xs badge-ghost">Inactive</span>
                    <% end %>
                  </div>
                  <%= if prompt.description do %>
                    <p class="text-xs text-base-content/55 leading-snug pl-5 line-clamp-2">
                      {prompt.description}
                    </p>
                  <% end %>
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
                    <span class="text-[10px] text-base-content/40 tabular-nums">
                      v{prompt.version}
                    </span>
                    <%= if prompt.tags do %>
                      <span class="text-base-content/20 text-xs">&middot;</span>
                      <span class="text-[10px] text-base-content/35 truncate">
                        {prompt.tags}
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="project-prompts-empty"
            icon="hero-chat-bubble-left-right"
            title={if @search_query != "", do: "No prompts found", else: "No prompts yet"}
            subtitle={
              if @search_query != "",
                do: "Try adjusting your search",
                else: "Create project-specific prompts to use with your agents"
            }
          />
        <% end %>
      </div>

      <%!-- Detail panel --%>
      <%= if @selected_prompt do %>
        <div class="hidden md:flex flex-col flex-1 overflow-hidden">
          <div class="flex-shrink-0 px-6 pt-5 pb-4 border-b border-base-content/8">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2 mb-1 flex-wrap">
                  <span class="text-base font-semibold text-base-content">
                    {@selected_prompt.name}
                  </span>
                  <span class={[
                    "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium",
                    if(is_nil(@selected_prompt.project_id),
                      do: "bg-primary/10 text-primary/70",
                      else: "bg-secondary/10 text-secondary/70"
                    )
                  ]}>
                    {if is_nil(@selected_prompt.project_id), do: "global", else: "project"}
                  </span>
                  <span class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-base-content/5 text-base-content/50">
                    v{@selected_prompt.version}
                  </span>
                  <%= if !@selected_prompt.active do %>
                    <span class="badge badge-xs badge-ghost">Inactive</span>
                  <% end %>
                </div>
                <p class="text-xs text-base-content/45 font-mono">{@selected_prompt.slug}</p>
                <%= if @selected_prompt.description do %>
                  <p class="text-sm text-base-content/60 mt-1.5 leading-snug">
                    {@selected_prompt.description}
                  </p>
                <% end %>
                <%= if @selected_prompt.tags do %>
                  <div class="flex flex-wrap gap-1 mt-2">
                    <%= for tag <- String.split(@selected_prompt.tags, ",", trim: true) do %>
                      <span class="badge badge-xs">
                        {String.trim(tag)}
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
              <.link
                navigate={~p"/projects/#{@project.id}/prompts/#{@selected_prompt.uuid}"}
                class="btn btn-ghost btn-xs gap-1 flex-shrink-0"
              >
                <.icon name="hero-arrow-top-right-on-square" class="size-3.5" /> Edit
              </.link>
            </div>
          </div>

          <div class="flex-1 overflow-y-auto px-6 py-5" style="scrollbar-width: none;">
            <div class="text-xs font-semibold text-base-content/40 uppercase tracking-wider mb-3">
              Prompt Text
            </div>
            <pre class="bg-base-200/50 rounded-lg px-4 py-4 text-xs font-mono text-base-content/80 whitespace-pre-wrap break-words leading-relaxed overflow-x-auto"><code>{@selected_prompt.prompt_text}</code></pre>

            <%= if @selected_prompt.created_by do %>
              <div class="mt-5 text-xs text-base-content/40">
                Created by <span class="text-base-content/60">{@selected_prompt.created_by}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

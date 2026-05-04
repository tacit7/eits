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
        project_id_str =
          socket.assigns.project_id && Integer.to_string(socket.assigns.project_id)

        if String.trim(query) != "" do
          Prompts.search_prompts(query, project_id_str)
        else
          Prompts.list_project_prompts(project_id_str)
        end
      end

    assign(socket, :prompts, prompts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <%= if @prompts != [] do %>
          <!-- Prompts List -->
          <div class="space-y-4" data-vim-list>
            <%= for prompt <- @prompts do %>
              <.link navigate={~p"/projects/#{@project.id}/prompts/#{prompt.uuid}"} class="block rounded-2xl [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50" data-vim-list-item>
                <div class="card bg-base-100 border border-base-300 hover:border-primary hover:shadow-md transition-all">
                  <div class="card-body">
                    <div class="flex items-start justify-between">
                      <div class="flex-1 min-w-0">
                        <!-- Prompt Name and Slug -->
                        <div class="flex items-center gap-3 mb-2">
                          <h3 class="text-base font-semibold text-base-content">
                            {prompt.name}
                          </h3>
                          <code class="text-xs font-mono text-base-content/60 bg-base-200 px-2 py-0.5 rounded">
                            {prompt.slug}
                          </code>
                          <%= if !prompt.active do %>
                            <span class="badge badge-sm badge-ghost">Inactive</span>
                          <% end %>
                        </div>
                        
    <!-- Description -->
                        <%= if prompt.description do %>
                          <p class="text-sm text-base-content/80 mb-2">
                            {prompt.description}
                          </p>
                        <% end %>
                        
    <!-- Meta Information -->
                        <div class="flex items-center gap-4 text-xs text-base-content/60">
                          <span class="flex items-center gap-1">
                            <.icon name="hero-clock" class="size-3" /> v{prompt.version}
                          </span>
                          <%= if prompt.tags do %>
                            <%= for tag <- String.split(prompt.tags, ",", trim: true) do %>
                              <span class="badge badge-xs">
                                {String.trim(tag)}
                              </span>
                            <% end %>
                          <% end %>
                          <%= if prompt.created_by do %>
                            <span>by {prompt.created_by}</span>
                          <% end %>
                        </div>
                      </div>
                      
    <!-- Chevron -->
                      <.icon
                        name="hero-chevron-right"
                        class="size-5 text-base-content/40 flex-shrink-0 mt-1"
                      />
                    </div>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% else %>
          <!-- Empty State -->
          <.empty_state
            id="project-prompts-empty"
            icon="hero-chat-bubble-left-right"
            title="No prompts yet"
            subtitle="Create project-specific prompts to use with your agents"
          />
        <% end %>
      </div>
    </div>
    """
  end
end

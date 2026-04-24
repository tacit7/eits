defmodule EyeInTheSkyWeb.ProjectLive.Prompts do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Prompts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project_id = parse_int(id)

    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)

        socket =
          socket
          |> assign(:page_title, "Prompts - #{project.name}")
          |> assign(:project, project)
          |> assign(:sidebar_tab, :prompts)
          |> assign(:sidebar_project, project)
          |> assign(:project_id, project_id)
          |> assign(:search_query, "")
          |> assign(:prompts, [])

        if connected?(socket), do: load_prompts(socket), else: socket
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:project_id, nil)
        |> assign(:search_query, "")
        |> assign(:prompts, [])
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

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
    project_id_str = Integer.to_string(socket.assigns.project_id)
    query = socket.assigns.search_query

    prompts =
      if query != "" and String.trim(query) != "" do
        Prompts.search_prompts(query, project_id_str)
      else
        Prompts.list_project_prompts(project_id_str)
      end

    assign(socket, :prompts, prompts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <!-- Search Input (mobile only — desktop uses top bar) -->
        <div class="mb-6 md:hidden">
          <form phx-change="search" class="w-full">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search prompts by name, description, or content..."
              class="input input-bordered w-full text-base"
              autocomplete="off"
            />
          </form>
        </div>

        <%= if @prompts != [] do %>
          <!-- Prompts List -->
          <div class="space-y-4">
            <%= for prompt <- @prompts do %>
              <a href={"/prompts/#{prompt.id}"} class="block">
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
                            <.icon name="hero-clock" class="w-3 h-3" /> v{prompt.version}
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
                        class="w-5 h-5 text-base-content/40 flex-shrink-0 mt-1"
                      />
                    </div>
                  </div>
                </div>
              </a>
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

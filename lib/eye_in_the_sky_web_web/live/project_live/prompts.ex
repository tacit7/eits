defmodule EyeInTheSkyWebWeb.ProjectLive.Prompts do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Prompts
  alias EyeInTheSkyWeb.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Parse project ID safely
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)
          |> Repo.preload([:agents])

        # Load tasks manually due to type mismatch
        tasks = Projects.get_project_tasks(project_id)

        socket
        |> assign(:page_title, "Prompts - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :prompts)
        |> assign(:sidebar_project, project)
        |> assign(:tasks, tasks)
        |> assign(:project_id, project_id)
        |> assign(:search_query, "")
        |> assign(:prompts, [])
        |> load_prompts()
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
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
        <!-- Search Input -->
        <div class="mb-6">
          <form phx-change="search" class="w-full">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search prompts by name, description, or content..."
              class="input input-bordered w-full"
              autocomplete="off"
            />
          </form>
        </div>

        <%= if length(@prompts) > 0 do %>
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
                            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
                              <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm7-3.25v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5a.75.75 0 0 1 1.5 0Z" />
                            </svg>
                            v{prompt.version}
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
                      <svg
                        class="w-5 h-5 text-base-content/40 flex-shrink-0 mt-1"
                        fill="currentColor"
                        viewBox="0 0 20 20"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
                          clip-rule="evenodd"
                        />
                      </svg>
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

defmodule EyeInTheSkyWebWeb.ProjectLive.Tasks do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWebWeb.Components.TaskCard

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

        socket
        |> assign(:page_title, "Tasks - #{project.name}")
        |> assign(:project, project)
        |> assign(:project_id, project_id)
        |> assign(:search_query, "")
        |> assign(:tasks, [])
        |> load_tasks()
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:project_id, nil)
        |> assign(:search_query, "")
        |> assign(:tasks, [])
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_tasks()

    {:noreply, socket}
  end

  defp load_tasks(socket) do
    project_id = socket.assigns.project_id
    query = socket.assigns.search_query

    tasks =
      if query != "" and String.trim(query) != "" do
        Tasks.search_tasks(query, project_id)
      else
        Projects.get_project_tasks(project_id)
      end

    assign(socket, :tasks, tasks)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EyeInTheSkyWebWeb.Components.Navbar}
      id="navbar"
      current_project={@project}
    />

    <EyeInTheSkyWebWeb.Components.ProjectNav.render
      project={@project}
      tasks={@tasks}
      current_tab={:tasks}
    />

    <!-- Search -->
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <form phx-change="search" class="w-full max-w-2xl">
        <input
          type="text"
          name="query"
          value={@search_query}
          placeholder="Search tasks by title or description..."
          class="input input-bordered w-full"
          autocomplete="off"
        />
      </form>
    </div>

    <!-- Tasks Grid -->
    <div class="px-4 sm:px-6 lg:px-8 pb-8">
      <%= if length(@tasks) > 0 do %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <%= for task <- @tasks do %>
            <TaskCard.task_card task={task} variant="grid" />
          <% end %>
        </div>
      <% else %>
        <!-- Empty State -->
        <div class="text-center py-16">
          <div class="mx-auto w-24 h-24 bg-base-200 rounded-full flex items-center justify-center mb-4">
            <svg
              class="w-12 h-12 text-base-content/40"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
              />
            </svg>
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">
            <%= if @search_query != "" do %>
              No tasks found
            <% else %>
              No tasks yet
            <% end %>
          </h3>
          <p class="text-sm text-base-content/60">
            <%= if @search_query != "" do %>
              Try adjusting your search query
            <% else %>
              Create a task to get started
            <% end %>
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end

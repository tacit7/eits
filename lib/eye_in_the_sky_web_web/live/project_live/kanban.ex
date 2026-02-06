defmodule EyeInTheSkyWebWeb.ProjectLive.Kanban do
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

        # Load workflow states
        workflow_states = Tasks.list_workflow_states()

        socket
        |> assign(:page_title, "Kanban - #{project.name}")
        |> assign(:project, project)
        |> assign(:project_id, project_id)
        |> assign(:search_query, "")
        |> assign(:workflow_states, workflow_states)
        |> assign(:tasks, [])
        |> assign(:tasks_by_state, %{})
        |> assign(:show_new_task_drawer, false)
        |> assign(:show_task_detail_drawer, false)
        |> assign(:selected_task, nil)
        |> load_tasks()
      else
        workflow_states = Tasks.list_workflow_states()

        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:project_id, nil)
        |> assign(:search_query, "")
        |> assign(:workflow_states, workflow_states)
        |> assign(:tasks, [])
        |> assign(:tasks_by_state, %{})
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

  @impl true
  def handle_event("toggle_new_task_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
  end

  @impl true
  def handle_event("toggle_task_detail_drawer", _params, socket) do
    {:noreply, assign(socket, :show_task_detail_drawer, !socket.assigns.show_task_detail_drawer)}
  end

  @impl true
  def handle_event("open_task_detail", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task!(task_id)

    socket =
      socket
      |> assign(:selected_task, task)
      |> assign(:show_task_detail_drawer, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_task", params, socket) do
    task = socket.assigns.selected_task
    title = params["title"]
    description = params["description"]
    state_id = String.to_integer(params["state_id"])
    priority = String.to_integer(params["priority"] || "0")
    due_at = if params["due_at"] != "", do: params["due_at"], else: nil
    tags_string = params["tags"] || ""

    # Parse tags
    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Update task
    case Tasks.update_task(task, %{
           title: title,
           description: description,
           state_id: state_id,
           priority: priority,
           due_at: due_at,
           updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, updated_task} ->
        # Handle tags
        if length(tag_names) > 0 do
          # Delete existing tags
          Repo.query("DELETE FROM task_tags WHERE task_id = ?", [task.id])

          # Add new tags
          Enum.each(tag_names, fn tag_name ->
            case Tasks.get_or_create_tag(tag_name) do
              {:ok, tag} ->
                Repo.query("INSERT INTO task_tags (task_id, tag_id) VALUES (?, ?)", [
                  task.id,
                  tag.id
                ])

              _ ->
                :ok
            end
          end)
        end

        # Reload task with associations
        updated_task = Tasks.get_task!(updated_task.id)

        socket =
          socket
          |> assign(:selected_task, updated_task)
          |> load_tasks()
          |> put_flash(:info, "Task updated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  @impl true
  def handle_event("delete_task", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task!(task_id)

    # Delete related records first to avoid foreign key constraint errors
    Repo.query("DELETE FROM task_tags WHERE task_id = ?", [task_id])
    Repo.query("DELETE FROM task_sessions WHERE task_id = ?", [task_id])
    Repo.query("DELETE FROM commit_tasks WHERE task_id = ?", [task_id])

    case Tasks.delete_task(task) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:show_task_detail_drawer, false)
          |> assign(:selected_task, nil)
          |> load_tasks()
          |> put_flash(:info, "Task deleted successfully")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  @impl true
  def handle_event("create_new_task", params, socket) do
    # Extract form data
    title = params["title"]
    description = params["description"]
    state_id = String.to_integer(params["state_id"])
    priority = String.to_integer(params["priority"] || "1")
    tags_string = params["tags"] || ""

    # Parse tags
    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Generate UUID for task
    task_id = String.upcase(Ecto.UUID.generate())
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Create task
    case Tasks.create_task(%{
           id: task_id,
           title: title,
           description: description,
           state_id: state_id,
           priority: priority,
           project_id: Integer.to_string(socket.assigns.project_id),
           created_at: now,
           updated_at: now
         }) do
      {:ok, task} ->
        # Add tags if provided
        if length(tag_names) > 0 do
          Enum.each(tag_names, fn tag_name ->
            case Tasks.get_or_create_tag(tag_name) do
              {:ok, tag} ->
                # Insert into task_tags join table
                Repo.query(
                  "INSERT INTO task_tags (task_id, tag_id) VALUES (?, ?)",
                  [task.id, tag.id]
                )

              _ ->
                :ok
            end
          end)
        end

        socket =
          socket
          |> assign(:show_new_task_drawer, false)
          |> load_tasks()
          |> put_flash(:info, "Task created successfully")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create task: #{inspect(changeset.errors)}")}
    end
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

    # Group tasks by state for kanban view
    tasks_by_state =
      Enum.group_by(tasks, fn task ->
        if task.state, do: task.state.id, else: nil
      end)

    socket
    |> assign(:tasks, tasks)
    |> assign(:tasks_by_state, tasks_by_state)
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
      current_tab={:kanban}
    />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <!-- Search Input and New Task Button -->
      <div class="max-w-7xl mx-auto mb-6 flex items-center gap-4">
        <form phx-change="search" class="flex-1 max-w-md">
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search tasks..."
            class="input input-bordered w-full input-sm"
            autocomplete="off"
          />
        </form>
        <button phx-click="toggle_new_task_drawer" class="btn btn-primary btn-sm">
          + New Task
        </button>
      </div>

      <%= if length(@tasks) > 0 do %>
        <!-- Kanban Board -->
        <div class="overflow-x-auto pb-4">
          <div class="inline-flex gap-4 min-w-full px-4">
            <%= for state <- @workflow_states do %>
              <div class="flex-shrink-0 w-80">
                <!-- Column Header -->
                <div class="bg-base-200 rounded-t-lg px-4 py-3">
                  <div class="flex items-center justify-between">
                    <h3 class="font-semibold text-sm text-base-content">
                      {state.name}
                    </h3>
                    <span class="badge badge-sm">
                      {length(Map.get(@tasks_by_state, state.id, []))}
                    </span>
                  </div>
                </div>
                
    <!-- Column Content -->
                <div class="bg-base-100 rounded-b-lg border border-base-300 border-t-0 p-3 min-h-[600px]">
                  <div class="space-y-3">
                    <%= for task <- Map.get(@tasks_by_state, state.id, []) do %>
                      <TaskCard.task_card
                        task={task}
                        variant="kanban"
                        on_click="open_task_detail"
                      />
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <!-- Empty State -->
        <div class="max-w-6xl mx-auto">
          <div class="text-center py-12">
            <svg
              class="mx-auto h-12 w-12 text-base-content/40"
              fill="currentColor"
              viewBox="0 0 16 16"
            >
              <path d="M2.5 1.75v11.5c0 .138.112.25.25.25h3.17a.75.75 0 0 1 .75.75V16L9.4 13.571c.13-.096.289-.196.601-.196h3.249a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H2.75a.25.25 0 0 0-.25.25Zm-1.5 0C1 .784 1.784 0 2.75 0h10.5C14.216 0 15 .784 15 1.75v11.5A1.75 1.75 0 0 1 13.25 15H10l-3.573 2.573A1.458 1.458 0 0 1 4 16.543V15H2.75A1.75 1.75 0 0 1 1 13.25Z" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-base-content">No tasks yet</h3>
            <p class="mt-1 text-sm text-base-content/60">
              Tasks will appear here when agents create them for this project
            </p>
          </div>
        </div>
      <% end %>
    </div>

    <!-- New Task Drawer -->
    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewTaskDrawer}
      id="new-task-drawer"
      show={@show_new_task_drawer}
      workflow_states={@workflow_states}
      toggle_event="toggle_new_task_drawer"
      submit_event="create_new_task"
    />

    <!-- Task Detail Drawer -->
    <.live_component
      module={EyeInTheSkyWebWeb.Components.TaskDetailDrawer}
      id="task-detail-drawer"
      show={@show_task_detail_drawer}
      task={@selected_task}
      workflow_states={@workflow_states}
      toggle_event="toggle_task_detail_drawer"
      update_event="update_task"
      delete_event="delete_task"
    />
    """
  end
end

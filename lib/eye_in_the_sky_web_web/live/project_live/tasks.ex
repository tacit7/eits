defmodule EyeInTheSkyWebWeb.ProjectLive.Tasks do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWebWeb.Components.TaskCard

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks")
    end

    # Parse project ID safely
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    workflow_states = Tasks.list_workflow_states()

    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)
          |> Repo.preload([:agents])

        socket
        |> assign(:page_title, "Tasks - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :tasks)
        |> assign(:sidebar_project, project)
        |> assign(:project_id, project_id)
        |> assign(:search_query, "")
        |> assign(:filter_state_id, nil)
        |> assign(:sort_by, "created_desc")
        |> assign(:workflow_states, workflow_states)
        |> assign(:show_new_task_drawer, false)
        |> assign(:show_task_detail_drawer, false)
        |> assign(:selected_task, nil)
        |> assign(:task_notes, [])
        |> assign(:tasks, [])
        |> load_tasks()
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:project_id, nil)
        |> assign(:search_query, "")
        |> assign(:filter_state_id, nil)
        |> assign(:sort_by, "created_desc")
        |> assign(:workflow_states, workflow_states)
        |> assign(:show_new_task_drawer, false)
        |> assign(:show_task_detail_drawer, false)
        |> assign(:selected_task, nil)
        |> assign(:task_notes, [])
        |> assign(:tasks, [])
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
      |> load_tasks()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_status", %{"state_id" => state_id}, socket) do
    state_id = if state_id == "", do: nil, else: String.to_integer(state_id)

    socket =
      socket
      |> assign(:filter_state_id, state_id)
      |> load_tasks()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_by", %{"value" => value}, socket) do
    socket =
      socket
      |> assign(:sort_by, value)
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
  def handle_event("keydown", %{"key" => "k", "ctrlKey" => true}, socket) do
    {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_task_detail", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    notes = Notes.list_notes_for_task(task.id)

    socket =
      socket
      |> assign(:selected_task, task)
      |> assign(:task_notes, notes)
      |> assign(:show_task_detail_drawer, true)

    {:noreply, socket}
  end

  def handle_event("open_task_detail", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_task", params, socket) do
    task = socket.assigns.selected_task
    title = params["title"]
    description = params["description"]
    state_id = parse_int(params["state_id"])
    priority = parse_int(params["priority"], 0)
    due_at = if params["due_at"] != "", do: params["due_at"], else: nil
    tags_string = params["tags"] || ""

    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case Tasks.update_task(task, %{
           title: title,
           description: description,
           state_id: state_id,
           priority: priority,
           due_at: due_at,
           updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, updated_task} ->
        Tasks.replace_task_tags(task.id, tag_names)

        updated_task = Tasks.get_task!(updated_task.id)

        socket =
          socket
          |> assign(:selected_task, updated_task)
          |> load_tasks()
          |> put_flash(:info, "Task updated")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  @impl true
  def handle_event("delete_task", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)

    case Tasks.delete_task_with_associations(task) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:show_task_detail_drawer, false)
          |> assign(:selected_task, nil)
          |> load_tasks()
          |> put_flash(:info, "Task deleted")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  @impl true
  def handle_event("start_agent_for_task", _params, socket) do
    {:noreply, put_flash(socket, :info, "Use the Kanban board to start agents for tasks")}
  end

  @impl true
  def handle_event("create_new_task", params, socket) do
    title = params["title"]
    description = params["description"]
    state_id = parse_int(params["state_id"])
    priority = parse_int(params["priority"], 1)
    tags_string = params["tags"] || ""

    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    task_uuid = String.upcase(Ecto.UUID.generate())
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    case Tasks.create_task(%{
           uuid: task_uuid,
           title: title,
           description: description,
           state_id: state_id,
           priority: priority,
           project_id: socket.assigns.project_id,
           created_at: now,
           updated_at: now
         }) do
      {:ok, task} ->
        Tasks.replace_task_tags(task.id, tag_names)

        socket =
          socket
          |> assign(:show_new_task_drawer, false)
          |> load_tasks()
          |> put_flash(:info, "Task created successfully")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create task: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_info(:tasks_changed, socket) do
    {:noreply, load_tasks(socket)}
  end

  defp parse_int(s, default \\ 0) do
    case Integer.parse(s || "") do
      {n, ""} -> n
      _ -> default
    end
  end

  defp load_tasks(socket) do
    project_id = socket.assigns.project_id
    query = socket.assigns.search_query
    filter_state_id = socket.assigns.filter_state_id
    sort_by = socket.assigns.sort_by

    tasks =
      if query != "" and String.trim(query) != "" do
        Tasks.search_tasks(query, project_id)
      else
        Projects.get_project_tasks(project_id,
          state_id: filter_state_id,
          sort_by: sort_by
        )
      end

    assign(socket, :tasks, tasks)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6" phx-hook="GlobalKeydown" id="project-tasks-page">
      <div class="max-w-4xl mx-auto">
        <%!-- Search and New Task --%>
        <div class="mb-4 flex items-center gap-3">
          <form phx-change="search" class="flex-1 max-w-sm">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
              </div>
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search tasks..."
                class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
                autocomplete="off"
              />
            </div>
          </form>

          <button
            phx-click="toggle_new_task_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Task
          </button>
        </div>

        <%!-- Filters --%>
        <div class="mb-4 flex items-center gap-2 flex-wrap">
          <%!-- Status filter pills --%>
          <button
            phx-click="filter_status"
            phx-value-state_id=""
            class={[
              "btn btn-xs gap-1 min-h-0 h-6",
              if(is_nil(@filter_state_id), do: "btn-neutral", else: "btn-ghost text-base-content/50")
            ]}
          >
            All
          </button>
          <%= for state <- @workflow_states do %>
            <button
              phx-click="filter_status"
              phx-value-state_id={state.id}
              class={[
                "btn btn-xs gap-1 min-h-0 h-6",
                if(@filter_state_id == state.id, do: "btn-neutral", else: "btn-ghost text-base-content/50")
              ]}
            >
              {state.name}
            </button>
          <% end %>

          <div class="flex-1" />

          <%!-- Sort dropdown --%>
          <form phx-change="sort_by">
            <select
              name="value"
              class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/60 min-h-0 h-6 text-xs"
            >
              <option value="created_desc" selected={@sort_by == "created_desc"}>Newest first</option>
              <option value="created_asc" selected={@sort_by == "created_asc"}>Oldest first</option>
              <option value="priority" selected={@sort_by == "priority"}>Priority</option>
            </select>
          </form>
        </div>

        <%!-- Task count --%>
        <div class="mb-3">
          <span class="text-[11px] font-mono tabular-nums text-base-content/30 tracking-wider uppercase">
            {length(@tasks)} tasks
          </span>
        </div>

        <%= if length(@tasks) > 0 do %>
          <div class="divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-5">
            <%= for task <- @tasks do %>
              <TaskCard.task_card task={task} variant="list" on_click="open_task_detail" on_delete="delete_task" />
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="project-tasks-empty"
            icon="hero-clipboard-document-list"
            title={if @search_query != "", do: "No tasks found", else: "No tasks yet"}
            subtitle={
              if @search_query != "",
                do: "Try adjusting your search query",
                else: "Create a task to get started"
            }
          />
        <% end %>
      </div>
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
      notes={@task_notes}
      workflow_states={@workflow_states}
      toggle_event="toggle_task_detail_drawer"
      update_event="update_task"
      delete_event="delete_task"
    />
    """
  end
end

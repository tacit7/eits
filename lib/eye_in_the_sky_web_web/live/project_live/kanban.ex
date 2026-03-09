defmodule EyeInTheSkyWebWeb.ProjectLive.Kanban do
  use EyeInTheSkyWebWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Sessions
  alias EyeInTheSkyWeb.Repo
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
        |> assign(:sidebar_tab, :kanban)
        |> assign(:sidebar_project, project)
        |> assign(:project_id, project_id)
        |> assign(:search_query, "")
        |> assign(:workflow_states, workflow_states)
        |> assign(:tasks, [])
        |> assign(:tasks_by_state, %{})
        |> assign(:show_new_task_drawer, false)
        |> assign(:show_task_detail_drawer, false)
        |> assign(:selected_task, nil)
        |> assign(:task_notes, [])
        |> assign(:quick_add_column, nil)
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
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
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
    task = Tasks.get_task_by_uuid!(task_id)

    # Load notes for this task (handles both "task" and "tasks" parent_type)
    notes = Notes.list_notes_for_task(task.id)

    socket =
      socket
      |> assign(:selected_task, task)
      |> assign(:task_notes, notes)
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
          Repo.delete_all(from t in "task_tags", where: t.task_id == ^task.id)

          # Add new tags
          Enum.each(tag_names, fn tag_name ->
            case Tasks.get_or_create_tag(tag_name) do
              {:ok, tag} ->
                Repo.insert_all("task_tags", [%{task_id: task.id, tag_id: tag.id}],
                  on_conflict: :nothing
                )

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
    task = Tasks.get_task_by_uuid!(task_id)

    # Delete related records first to avoid foreign key constraint errors
    Repo.delete_all(from t in "task_tags", where: t.task_id == ^task.id)
    Repo.delete_all(from t in "task_sessions", where: t.task_id == ^task.id)
    Repo.delete_all(from t in "commit_tasks", where: t.task_id == ^task.id)

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
  def handle_event("start_agent_for_task", %{"task_id" => task_id}, socket) do
    alias EyeInTheSkyWeb.{Agents, Claude.SessionManager}

    task = Tasks.get_task_by_uuid!(task_id)
    project = socket.assigns.project

    session_id = Ecto.UUID.generate()
    agent_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    task_prompt = "#{task.title}\n\n#{task.description || ""}" |> String.trim()

    case Agents.create_agent(%{
           uuid: agent_id,
           description: task_prompt,
           project_id: project.id,
           git_worktree_path: project.path
         }) do
      {:ok, agent} ->
        case Sessions.create_session_with_model(%{
               uuid: session_id,
               agent_id: agent.id,
               name: task.title,
               description: task_prompt,
               started_at: now,
               model_provider: "claude",
               model_name: "sonnet"
             }) do
          {:ok, session} ->
            # Link task to session
            Repo.insert_all("task_sessions", [%{task_id: task.id, session_id: session.id}],
              on_conflict: :nothing
            )

            init_prompt = """
            INITIALIZATION - Eye in the Sky Session:

            Session ID: #{session_id}
            Agent ID: #{agent_id}
            Project: #{project.name}
            Task ID: #{task_id}

            CRITICAL FIRST STEP: Call i-start-session MCP tool to register with Eye in the Sky:

            mcp__eye-in-the-sky__i-start-session({
              "session_id": "#{session_id}",
              "description": "#{task_prompt}",
              "agent_description": "Agent for task #{String.slice(task_id, 0..7)}",
              "project_name": "#{project.name}",
              "worktree_path": "#{project.path}"
            })

            WORKFLOW:
            1. Use i-start-session to register (done above)
            2. Log significant actions with i-note-add
            3. Track tasks with i-todo-create and i-todo-list
            4. Use i-end-session when done

            YOUR TASK: #{task_prompt}

            Ready to start working.
            """

            Task.Supervisor.start_child(EyeInTheSkyWeb.TaskSupervisor, fn ->
              SessionManager.start_session(session_id, init_prompt,
                model: "sonnet",
                project_path: project.path
              )
            end)

            socket =
              socket
              |> assign(:show_task_detail_drawer, false)
              |> put_flash(:info, "Agent spawned for task: #{String.slice(task.title, 0..40)}")

            {:noreply, socket}

          {:error, changeset} ->
            {:noreply,
             put_flash(socket, :error, "Failed to create session: #{inspect(changeset.errors)}")}
        end

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create agent: #{inspect(changeset.errors)}")}
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
    task_uuid = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Create task
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
        # Add tags if provided
        if length(tag_names) > 0 do
          Enum.each(tag_names, fn tag_name ->
            case Tasks.get_or_create_tag(tag_name) do
              {:ok, tag} ->
                Repo.insert_all("task_tags", [%{task_id: task.id, tag_id: tag.id}],
                  on_conflict: :nothing
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
        {:noreply,
         put_flash(socket, :error, "Failed to create task: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_info(:tasks_changed, socket) do
    {:noreply, load_tasks(socket)}
  end

  @impl true
  def handle_event("move_task", %{"task_id" => task_uuid, "state_id" => state_id_str}, socket) do
    state_id = String.to_integer(state_id_str)
    task = Tasks.get_task_by_uuid!(task_uuid)

    case Tasks.update_task(task, %{
           state_id: state_id,
           updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks", :tasks_changed)
        {:noreply, load_tasks(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to move task")}
    end
  end

  @impl true
  def handle_event("show_quick_add", %{"state_id" => state_id}, socket) do
    {:noreply, assign(socket, :quick_add_column, String.to_integer(state_id))}
  end

  @impl true
  def handle_event("hide_quick_add", _params, socket) do
    {:noreply, assign(socket, :quick_add_column, nil)}
  end

  @impl true
  def handle_event("quick_add_task", %{"title" => title, "state_id" => state_id_str}, socket) do
    title = String.trim(title)

    if title == "" do
      {:noreply, assign(socket, :quick_add_column, nil)}
    else
      state_id = String.to_integer(state_id_str)
      task_uuid = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      case Tasks.create_task(%{
             uuid: task_uuid,
             title: title,
             state_id: state_id,
             priority: 0,
             project_id: socket.assigns.project_id,
             created_at: now,
             updated_at: now
           }) do
        {:ok, _task} ->
          socket =
            socket
            |> assign(:quick_add_column, nil)
            |> load_tasks()

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create task")}
      end
    end
  end

  defp format_due(nil), do: ""

  defp format_due(datetime) when is_binary(datetime) do
    case Date.from_iso8601(String.slice(datetime, 0..9)) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          Date.compare(date, today) == :eq -> "Today"
          Date.compare(date, Date.add(today, 1)) == :eq -> "Tomorrow"
          Date.compare(date, today) == :lt -> "Overdue"
          true -> Calendar.strftime(date, "%b %d")
        end

      _ ->
        datetime
    end
  end

  defp format_due(_), do: ""

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

  defp state_dot_color(color) when is_binary(color), do: color
  defp state_dot_color(_), do: "#6B7280"

  defp priority_border_class(nil), do: "border-l-transparent"
  defp priority_border_class(0), do: "border-l-transparent"
  defp priority_border_class(priority) when priority >= 3, do: "border-l-error"
  defp priority_border_class(2), do: "border-l-warning"
  defp priority_border_class(1), do: "border-l-info"
  defp priority_border_class(_), do: "border-l-transparent"

  defp due_date_class(nil), do: "text-base-content/30"

  defp due_date_class(datetime) when is_binary(datetime) do
    case Date.from_iso8601(String.slice(datetime, 0..9)) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          Date.compare(date, today) == :lt -> "text-error font-medium"
          Date.compare(date, today) == :eq -> "text-warning font-medium"
          true -> "text-base-content/30"
        end

      _ ->
        "text-base-content/30"
    end
  end

  defp due_date_class(_), do: "text-base-content/30"

  defp first_line(nil), do: nil
  defp first_line(""), do: nil

  defp first_line(text) do
    text
    |> String.split(~r/[\r\n]/, parts: 2)
    |> List.first()
    |> String.trim()
    |> case do
      "" -> nil
      line -> line
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 py-6 h-[calc(100vh-4rem)] flex flex-col">
      <%!-- Search + New Task --%>
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
              phx-debounce="300"
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

      <%!-- Kanban columns --%>
      <div class="flex-1 min-h-0 overflow-x-auto">
        <div class="inline-flex gap-3 h-full min-w-full pb-2">
          <%= for state <- @workflow_states do %>
            <% column_tasks = Map.get(@tasks_by_state, state.id, []) %>
            <div class="flex-shrink-0 w-72 flex flex-col h-full">
              <%!-- Column header with colored accent --%>
              <div class="mb-2">
                <div
                  class="h-0.5 rounded-full mx-1 mb-2"
                  style={"background-color: #{state_dot_color(state.color)}"}
                />
                <div class="flex items-center gap-2 px-3 py-1">
                  <div
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    style={"background-color: #{state_dot_color(state.color)}"}
                  />
                  <span class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                    {state.name}
                  </span>
                  <span class="ml-auto inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-full bg-base-content/[0.06] text-[11px] font-medium tabular-nums text-base-content/40">
                    {length(column_tasks)}
                  </span>
                </div>
              </div>

              <%!-- Column body --%>
              <div
                class="flex-1 min-h-0 overflow-y-auto rounded-xl bg-base-content/[0.04] p-2 space-y-1.5"
                id={"kanban-col-#{state.id}"}
                phx-hook="SortableKanban"
                data-state-id={state.id}
              >
                <%= if column_tasks == [] do %>
                  <div data-empty-placeholder class="flex flex-col items-center justify-center h-24 border border-dashed border-base-content/8 rounded-lg pointer-events-none">
                    <.icon name="hero-inbox" class="w-5 h-5 text-base-content/15 mb-1" />
                    <span class="text-[11px] text-base-content/20">No tasks</span>
                  </div>
                <% end %>
                <%= for task <- column_tasks do %>
                  <div
                    class="group/card relative rounded-lg bg-base-100 dark:bg-[hsl(60,2.1%,18.4%)] px-3 py-2 cursor-pointer hover:bg-base-200/80 dark:hover:bg-[hsl(60,2%,21%)] transition-colors"
                    phx-click="open_task_detail"
                    phx-value-task_id={task.uuid}
                    data-task-id={task.uuid}
                    id={"kanban-task-#{task.id}"}
                  >
                    <span class={[
                      "text-sm font-medium leading-snug pr-5",
                      task.completed_at && "text-base-content/40 line-through",
                      !task.completed_at && "text-base-content/85"
                    ]}>
                      {task.title}
                    </span>
                    <%= if task.due_at || (task.description && task.description != "") do %>
                      <div class="flex items-center gap-2 mt-1.5 text-base-content/30">
                        <%= if task.due_at do %>
                          <span class={[
                            "flex items-center gap-1 text-[11px]",
                            due_date_class(task.due_at)
                          ]}>
                            <.icon name="hero-clock-mini" class="w-3.5 h-3.5" />
                            {format_due(task.due_at)}
                          </span>
                        <% end %>
                        <%= if task.description && task.description != "" do %>
                          <.icon name="hero-bars-3-bottom-left-mini" class="w-3.5 h-3.5" />
                        <% end %>
                      </div>
                    <% end %>
                    <button
                      type="button"
                      phx-click="delete_task"
                      phx-value-task_id={task.uuid}
                      data-confirm="Delete this task?"
                      class="absolute top-1.5 right-1.5 opacity-0 group-hover/card:opacity-100 w-5 h-5 flex items-center justify-center rounded text-base-content/25 hover:text-error hover:bg-error/10 transition-all"
                    >
                      <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
                    </button>
                  </div>
                <% end %>

                <%!-- Quick-add --%>
                <%= if @quick_add_column == state.id do %>
                  <form phx-submit="quick_add_task" class="mt-1">
                    <input type="hidden" name="state_id" value={state.id} />
                    <input
                      type="text"
                      name="title"
                      placeholder="Task title... (Esc to cancel)"
                      autofocus
                      phx-keydown="hide_quick_add"
                      phx-key="Escape"
                      class="input input-sm w-full bg-base-100 dark:bg-[hsl(60,2.1%,18.4%)] border-base-content/10 text-sm placeholder:text-base-content/25 focus:border-primary/30"
                    />
                  </form>
                <% else %>
                  <button
                    phx-click="show_quick_add"
                    phx-value-state_id={state.id}
                    class="mt-1 w-full flex items-center gap-1.5 px-2 py-1.5 rounded-lg text-[11px] text-base-content/25 hover:text-base-content/50 hover:bg-base-content/[0.04] transition-colors"
                  >
                    <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
                    <span>Add task</span>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewTaskDrawer}
      id="new-task-drawer"
      show={@show_new_task_drawer}
      workflow_states={@workflow_states}
      toggle_event="toggle_new_task_drawer"
      submit_event="create_new_task"
    />

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

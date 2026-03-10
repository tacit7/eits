defmodule EyeInTheSkyWebWeb.OverviewLive.Tasks do
  use EyeInTheSkyWebWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWebWeb.Components.TaskCard

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks")
    end

    workflow_states = Tasks.list_workflow_states()

    socket =
      socket
      |> assign(:page_title, "All Tasks")
      |> assign(:search_query, "")
      |> assign(:workflow_states, workflow_states)
      |> assign(:state_filter, "all")
      |> assign(:tasks, [])
      |> assign(:sidebar_tab, :tasks)
      |> assign(:sidebar_project, nil)
      |> assign(:show_task_detail_drawer, false)
      |> assign(:selected_task, nil)
      |> assign(:task_notes, [])
      |> load_tasks()

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
  def handle_event("filter_state", %{"state" => state}, socket) do
    socket =
      socket
      |> assign(:state_filter, state)
      |> load_tasks()

    {:noreply, socket}
  end

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

  @impl true
  def handle_event("toggle_task_detail_drawer", _params, socket) do
    {:noreply, assign(socket, :show_task_detail_drawer, !socket.assigns.show_task_detail_drawer)}
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
        if length(tag_names) > 0 do
          Repo.delete_all(from t in "task_tags", where: t.task_id == ^task.id)

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
          |> put_flash(:info, "Task deleted")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  @impl true
  def handle_event("start_agent_for_task", _params, socket) do
    {:noreply, put_flash(socket, :info, "Open the project Kanban board to start agents")}
  end

  @impl true
  def handle_info(:tasks_changed, socket) do
    {:noreply, load_tasks(socket)}
  end

  defp load_tasks(socket) do
    query = socket.assigns.search_query
    state_filter = socket.assigns.state_filter

    tasks =
      if query != "" and String.trim(query) != "" do
        Tasks.search_tasks(query)
      else
        Tasks.list_tasks()
      end

    tasks =
      case state_filter do
        "all" ->
          tasks

        state_id_str ->
          case Integer.parse(state_id_str) do
            {state_id, ""} -> Enum.filter(tasks, &(&1.state_id == state_id))
            _ -> tasks
          end
      end

    assign(socket, :tasks, tasks)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <%!-- Search + State filters --%>
        <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center">
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

          <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
            <button
              phx-click="filter_state"
              phx-value-state="all"
              class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                if(@state_filter == "all",
                  do: "bg-base-100 text-base-content shadow-sm",
                  else: "text-base-content/40 hover:text-base-content/60"
                )}
            >
              All
            </button>
            <%= for state <- @workflow_states do %>
              <button
                phx-click="filter_state"
                phx-value-state={to_string(state.id)}
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@state_filter == to_string(state.id),
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                {state.name}
              </button>
            <% end %>
          </div>
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
            id="overview-tasks-empty"
            icon="hero-clipboard-document-list"
            title={
              if @search_query != "" || @state_filter != "all",
                do: "No tasks found",
                else: "No tasks yet"
            }
            subtitle={
              if @search_query != "" || @state_filter != "all",
                do: "Try adjusting your search or filters",
                else: "Tasks created by agents will appear here"
            }
          />
        <% end %>
      </div>
    </div>

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

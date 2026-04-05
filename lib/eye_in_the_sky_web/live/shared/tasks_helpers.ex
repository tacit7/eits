defmodule EyeInTheSkyWeb.Live.Shared.TasksHelpers do
  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 2]

  alias EyeInTheSky.{Tasks, Notes}

  # ---------------------------------------------------------------------------
  # Event handlers with no dependency on per-LiveView private functions
  # ---------------------------------------------------------------------------

  def handle_open_filter_sheet(_params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, true)}
  end

  def handle_close_filter_sheet(_params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, false)}
  end

  def handle_open_task_detail(%{"task_id" => task_id} = params, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    notes = Notes.list_notes_for_task(task.id)
    focus = Map.get(params, "focus")

    {:noreply,
     socket
     |> assign(:selected_task, task)
     |> assign(:task_notes, notes)
     |> assign(:task_detail_focus, focus)
     |> assign(:show_task_detail_drawer, true)}
  end

  def handle_open_task_detail(_params, socket), do: {:noreply, socket}

  # Variant for LiveViews that use an `active_overlay` atom rather than a boolean drawer assign.
  def handle_open_task_detail_with_overlay(%{"task_id" => task_id}, socket, overlay_value) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    notes = Notes.list_notes_for_task(task.id)

    {:noreply,
     socket
     |> assign(:selected_task, task)
     |> assign(:task_notes, notes)
     |> assign(:active_overlay, overlay_value)}
  end

  def handle_open_task_detail_with_overlay(_params, socket, _overlay_value),
    do: {:noreply, socket}

  def handle_toggle_task_detail_drawer(_params, socket) do
    {:noreply, assign(socket, :show_task_detail_drawer, !socket.assigns.show_task_detail_drawer)}
  end

  # ---------------------------------------------------------------------------
  # Event handlers that require a reload_fn callback
  # Each LiveView passes its own load_tasks/1 or load_tasks_page/2.
  # ---------------------------------------------------------------------------

  def handle_search(%{"query" => query}, socket, reload_fn) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    {:noreply,
     socket
     |> assign(:search_query, effective_query)
     |> reload_fn.()}
  end

  def handle_load_more(_params, socket, load_page_fn) do
    if socket.assigns.has_more do
      next_page = socket.assigns.page + 1
      {:noreply, load_page_fn.(socket, next_page)}
    else
      {:noreply, socket}
    end
  end

  def handle_update_task(params, socket, reload_fn) do
    task = socket.assigns.selected_task
    title = params["title"]
    description = params["description"]
    state_id = parse_int(params["state_id"], 0)
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
           updated_at: DateTime.utc_now()
         }) do
      {:ok, updated_task} ->
        Tasks.replace_task_tags(task.id, tag_names)
        updated_task = Tasks.get_task!(updated_task.id)

        {:noreply,
         socket
         |> assign(:selected_task, updated_task)
         |> reload_fn.()
         |> put_flash(:info, "Task updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  def handle_delete_task(%{"task_id" => task_id}, socket, reload_fn) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)

    case Tasks.delete_task_with_associations(task) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:show_task_detail_drawer, false)
         |> assign(:selected_task, nil)
         |> reload_fn.()
         |> put_flash(:info, "Task deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  def handle_archive_task(%{"task_id" => task_id}, socket, reload_fn) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)

    case Tasks.archive_task(task) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:show_task_detail_drawer, false)
         |> assign(:selected_task, nil)
         |> reload_fn.()
         |> put_flash(:info, "Task archived")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to archive task")}
    end
  end

  def handle_add_task_annotation(%{"task_id" => task_id, "body" => body}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    body = String.trim(body)

    if body != "" do
      case Notes.create_note(%{
             parent_type: "task",
             parent_id: task.uuid || to_string(task.id),
             body: body
           }) do
        {:ok, _note} ->
          notes = Notes.list_notes_for_task(task.id)
          {:noreply, assign(socket, :task_notes, notes)}

        {:error, changeset} ->
          Logger.error("Failed to create task annotation: #{inspect(changeset.errors)}")
          {:noreply, put_flash(socket, :error, "Failed to save annotation")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_create_new_task(params, socket, reload_fn) do
    project_id = socket.assigns[:project_id]
    session_id = socket.assigns[:session_id]

    title = params["title"]
    description = params["description"]
    state_id = parse_form_int(params["state_id"], 0)
    priority = parse_form_int(params["priority"], 1)
    tags_string = params["tags"] || ""

    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    now = DateTime.utc_now()

    task_attrs = %{
      uuid: Ecto.UUID.generate(),
      title: title,
      description: description,
      state_id: if(state_id > 0, do: state_id, else: Tasks.WorkflowState.todo_id()),
      priority: priority,
      created_at: now,
      updated_at: now
    }

    task_attrs = if project_id, do: Map.put(task_attrs, :project_id, project_id), else: task_attrs

    case Tasks.create_task(task_attrs) do
      {:ok, task} ->
        if tag_names != [], do: Tasks.replace_task_tags(task.id, tag_names)
        if session_id, do: Tasks.link_session_to_task(task.id, session_id)

        {:noreply,
         socket
         |> assign(:show_new_task_drawer, false)
         |> assign(:show_create_task_drawer, false)
         |> reload_fn.()
         |> put_flash(:info, "Task created")}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create task: #{inspect(changeset.errors)}")}
    end
  end

  def handle_quick_add_task(%{"title" => title, "state_id" => state_id_str}, socket, reload_fn) do
    title = String.trim(title)

    if title == "" do
      {:noreply, assign(socket, :quick_add_column, nil)}
    else
      state_id = parse_int(state_id_str, 0)

      case Tasks.quick_create_task(title, state_id, socket.assigns.project_id) do
        {:ok, _task} ->
          {:noreply,
           socket
           |> assign(:quick_add_column, nil)
           |> reload_fn.()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create task")}
      end
    end
  end

  def handle_tasks_changed(socket, reload_fn) do
    {:noreply, reload_fn.(socket)}
  end

  def handle_copy_task_to_project(%{"project_id" => project_id_str}, socket) do
    task = socket.assigns.selected_task
    target_project_id = parse_int(project_id_str, 0)

    if target_project_id > 0 and task do
      do_copy_task(task, target_project_id, socket)
    else
      {:noreply, socket}
    end
  end

  defp do_copy_task(task, target_project_id, socket) do
    now = DateTime.utc_now()
    tag_names = Enum.map(task.tags || [], & &1.name)

    case Tasks.create_task(%{
           uuid: Ecto.UUID.generate(),
           title: task.title,
           description: task.description,
           state_id: EyeInTheSky.Tasks.WorkflowState.todo_id(),
           priority: task.priority || 0,
           project_id: target_project_id,
           created_at: now,
           updated_at: now
         }) do
      {:ok, new_task} ->
        if tag_names != [], do: Tasks.replace_task_tags(new_task.id, tag_names)
        target = EyeInTheSky.Projects.get_project!(target_project_id)

        {:noreply,
         socket
         |> assign(:show_task_detail_drawer, false)
         |> put_flash(:info, "Task copied to #{target.name}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to copy task")}
    end
  end

  # Lenient integer parser for form params. Accepts trailing chars ("2 " → 2)
  # unlike ControllerHelpers.parse_int which requires exact match ("2 " → default).
  defp parse_form_int(nil, default), do: default
  defp parse_form_int(val, _default) when is_integer(val), do: val

  defp parse_form_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_form_int(_, default), do: default
end

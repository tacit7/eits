defmodule EyeInTheSkyWeb.Components.Rail.RailStateActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3, start_async: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Claude.RateLimitClient
  alias EyeInTheSky.{Prompts, Tasks}
  alias EyeInTheSky.Projects.FileTree
  alias EyeInTheSkyWeb.Components.Rail.Loader

  def handle_refresh_usage(params, socket) do
    _ = params
    {:noreply,
     socket
     |> assign(:flyout_usage, nil)
     |> start_async(:load_usage, fn -> RateLimitClient.force_refresh() end)}
  end

  def handle_restore_rail_state(params, socket) do
    socket =
      socket
      |> maybe_restore_project(params)
      |> maybe_restore_section(params)
      |> maybe_restore_session_sort(params)
      |> maybe_restore_session_scope(params)
      |> maybe_restore_session_show(params)
      |> maybe_restore_task_state_filter(params)
      |> maybe_restore_team_status(params)
      |> maybe_restore_file_expanded(params)

    {:noreply, socket}
  end

  def handle_toggle_proj_picker(params, socket) do
    _ = params
    {:noreply, assign(socket, :proj_picker_open, !socket.assigns.proj_picker_open)}
  end

  def handle_close_proj_picker(params, socket) do
    _ = params
    {:noreply, assign(socket, :proj_picker_open, false)}
  end

  def handle_open_mobile(params, socket) do
    _ = params
    {:noreply, assign(socket, mobile_open: true, flyout_open: true)}
  end

  def handle_new_note(params, socket) do
    _ = params
    {:noreply, push_navigate(socket, to: "/notes/new")}
  end

  def handle_not_implemented(params, socket) do
    _ = params
    {:noreply, put_flash(socket, :info, "Not implemented yet")}
  end

  def handle_show_more_project_sessions(%{"project_id" => pid_str}, socket) do
    case parse_int(pid_str) do
      nil -> {:noreply, socket}
      pid ->
        current = Map.get(socket.assigns.session_project_visible, pid, 5)

        {:noreply,
         assign(
           socket,
           :session_project_visible,
           Map.put(socket.assigns.session_project_visible, pid, current + 5)
         )}
    end
  end

  def handle_toggle_project_sessions(%{"project_id" => pid_str}, socket) do
    case parse_int(pid_str) do
      nil -> {:noreply, socket}
      pid ->
        collapsed = socket.assigns.session_project_collapsed

        updated =
          if MapSet.member?(collapsed, pid),
            do: MapSet.delete(collapsed, pid),
            else: MapSet.put(collapsed, pid)

        {:noreply, assign(socket, :session_project_collapsed, updated)}
    end
  end

  def handle_open_rail_modal(%{"type" => type}, socket) do
    modal =
      case type do
        "new_task" -> :new_task
        "new_prompt" -> :new_prompt
        _ -> nil
      end

    {:noreply, assign(socket, :rail_modal, modal)}
  end

  def handle_open_task_detail(%{"task_id" => task_id_str}, socket) do
    case parse_int(task_id_str) do
      nil -> {:noreply, socket}
      task_id ->
        tasks = socket.assigns.flyout_tasks
        index = Enum.find_index(tasks, &(&1.id == task_id)) || 0
        {:noreply, assign(socket, :rail_modal, {:view_task, index, tasks})}
    end
  end

  def handle_task_detail_nav(%{"dir" => dir}, socket) do
    {:view_task, index, tasks} = socket.assigns.rail_modal
    count = length(tasks)
    new_index = rem(index + if(dir == "next", do: 1, else: count - 1), count)
    {:noreply, assign(socket, :rail_modal, {:view_task, new_index, tasks})}
  end

  def handle_open_note_detail(%{"note_id" => note_id_str}, socket) do
    case parse_int(note_id_str) do
      nil -> {:noreply, socket}
      note_id ->
        notes = socket.assigns.flyout_notes
        index = Enum.find_index(notes, &(&1.id == note_id)) || 0
        {:noreply, assign(socket, :rail_modal, {:view_note, index, notes})}
    end
  end

  def handle_note_detail_nav(%{"dir" => dir}, socket) do
    {:view_note, index, notes} = socket.assigns.rail_modal
    count = length(notes)
    new_index = rem(index + if(dir == "next", do: 1, else: count - 1), count)
    {:noreply, assign(socket, :rail_modal, {:view_note, new_index, notes})}
  end

  def handle_close_rail_modal(params, socket) do
    _ = params
    {:noreply, assign(socket, :rail_modal, nil)}
  end

  def handle_submit_rail_modal(params, socket) do
    title = String.trim(params["title"] || "")
    body = String.trim(params["body"] || "")
    modal_type = socket.assigns.rail_modal
    project_id = socket.assigns.sidebar_project && socket.assigns.sidebar_project.id

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title is required")}
    else
      result =
        case modal_type do
          :new_task ->
            Tasks.create_task(%{title: title, body: body, state_id: 1, project_id: project_id})

          :new_prompt ->
            Prompts.create_prompt(%{title: title, body: body, project_id: project_id})

          _ ->
            {:error, :unknown}
        end

      case result do
        {:ok, _} ->
          socket = assign(socket, :rail_modal, nil)

          socket =
            case modal_type do
              :new_task ->
                assign(
                  socket,
                  :flyout_tasks,
                  Loader.load_flyout_tasks(
                    socket.assigns.sidebar_project,
                    socket.assigns.task_search,
                    socket.assigns.task_state_filter
                  )
                )

              _ ->
                socket
            end

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create")}
      end
    end
  end

  # --- localStorage restore helpers ---
  # Each guards against missing/bad data. A bad value is silently skipped so a
  # corrupted localStorage entry never crashes the LiveComponent.

  defp maybe_restore_project(socket, %{"project_id" => id}) when not is_nil(id) do
    # Only restore when the parent LiveView hasn't already set a project.
    # update/2 runs before the hook fires, so a route-scoped project wins.
    if is_nil(socket.assigns.sidebar_project) do
      alias EyeInTheSkyWeb.Components.Rail.ProjectActions
      ProjectActions.handle_restore_project(to_string(id), socket)
      |> then(fn {:noreply, s} -> s end)
    else
      socket
    end
  end

  defp maybe_restore_project(socket, _), do: socket

  defp maybe_restore_section(socket, %{"section" => section}) when is_binary(section) do
    assign(socket, :active_section, Loader.parse_section(section))
  end

  defp maybe_restore_section(socket, _), do: socket

  defp maybe_restore_session_sort(socket, %{"session_sort" => sort}) when is_binary(sort) do
    assign(socket, :session_sort, Loader.parse_session_sort(sort))
  end

  defp maybe_restore_session_sort(socket, _), do: socket

  defp maybe_restore_session_scope(socket, %{"session_scope" => scope})
       when scope in ["current", "all"] do
    assign(socket, :session_scope, String.to_existing_atom(scope))
  end

  defp maybe_restore_session_scope(socket, _), do: socket

  defp maybe_restore_session_show(socket, %{"session_show" => show}) when is_binary(show) do
    assign(socket, :session_show, Loader.parse_session_show(show))
  end

  defp maybe_restore_session_show(socket, _), do: socket

  defp maybe_restore_task_state_filter(socket, %{"task_state_filter" => id})
       when id in [1, 2, 3, 4] do
    assign(socket, :task_state_filter, id)
  end

  # Defensive: JSON may sometimes arrive as a string if the value was stored
  # before integer encoding was guaranteed (e.g. migrated from an older blob).
  defp maybe_restore_task_state_filter(socket, %{"task_state_filter" => id})
       when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed in [1, 2, 3, 4] ->
        assign(socket, :task_state_filter, parsed)

      _ ->
        socket
    end
  end

  defp maybe_restore_task_state_filter(socket, _), do: socket

  defp maybe_restore_team_status(socket, %{"team_status" => status})
       when status in ["active", "archived"] do
    assign(socket, :team_status, status)
  end

  defp maybe_restore_team_status(socket, _), do: socket

  defp maybe_restore_file_expanded(socket, %{"file_expanded" => paths}) when is_list(paths) do
    # Cap at 100 paths to avoid excessive filesystem reads on mount.
    valid_paths = paths |> Enum.filter(&is_binary/1) |> Enum.take(100)

    # Re-fetch children for restored paths if a project with a disk path is set.
    # Without this, the expanded state would render folders as open but with no children.
    case socket.assigns.sidebar_project do
      %{path: root} when not is_nil(root) ->
        children =
          Enum.reduce(valid_paths, %{}, fn path, acc ->
            case FileTree.children(root, path) do
              {:ok, nodes} -> Map.put(acc, path, nodes)
              {:error, _} -> acc
            end
          end)

        # Only keep paths that successfully loaded children.
        valid_expanded = MapSet.new(Map.keys(children))

        socket
        |> assign(:flyout_file_expanded, valid_expanded)
        |> assign(:flyout_file_children, children)

      _ ->
        assign(socket, :flyout_file_expanded, MapSet.new(valid_paths))
    end
  end

  defp maybe_restore_file_expanded(socket, _), do: socket
end

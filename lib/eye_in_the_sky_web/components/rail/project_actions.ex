defmodule EyeInTheSkyWeb.Components.Rail.ProjectActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, push_navigate: 2, push_event: 3, put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Projects
  alias EyeInTheSkyWeb.Components.Rail.Loader

  def handle_select_project(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        current_id = get_in(socket.assigns, [:sidebar_project, Access.key(:id)])

        if current_id == id do
          {:noreply, assign(socket, :sidebar_project, nil)}
        else
          case Projects.get_project(id) do
            {:ok, project} -> {:noreply, assign(socket, :sidebar_project, project)}
            {:error, _} -> {:noreply, socket}
          end
        end
    end
  end

  def handle_start_rename(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil -> {:noreply, socket}
      id ->
        case Projects.get_project(id) do
          {:ok, project} -> {:noreply, assign(socket, renaming_project_id: id, rename_value: project.name)}
          {:error, _} -> {:noreply, socket}
        end
    end
  end

  def handle_cancel_rename(socket),
    do: {:noreply, assign(socket, renaming_project_id: nil, rename_value: "")}

  def handle_update_rename_value(%{"value" => value}, socket),
    do: {:noreply, assign(socket, :rename_value, value)}

  def handle_commit_rename(socket) do
    name = String.trim(socket.assigns.rename_value)
    project_id = socket.assigns.renaming_project_id

    if name == "" or is_nil(project_id) do
      {:noreply, assign(socket, renaming_project_id: nil, rename_value: "")}
    else
      case Projects.get_project(project_id) do
        {:ok, project} ->
          case Projects.update_project(project, %{name: name}) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:projects, Projects.list_projects_for_sidebar())
               |> assign(:renaming_project_id, nil)
               |> assign(:rename_value, "")}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to rename project")
               |> assign(:projects, Projects.list_projects_for_sidebar())
               |> assign(:renaming_project_id, nil)
               |> assign(:rename_value, "")}
          end

        {:error, _} ->
          # Project deleted while rename UI was open — reload to clear stale entry.
          {:noreply,
           socket
           |> put_flash(:error, "Project not found")
           |> assign(:projects, Projects.list_projects_for_sidebar())
           |> assign(:renaming_project_id, nil)
           |> assign(:rename_value, "")}
      end
    end
  end

  def handle_delete_project(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil -> {:noreply, socket}
      id ->
        case Projects.get_project(id) do
          {:ok, project} -> Projects.delete_project(project)
          {:error, _} -> :ok
        end
        {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
    end
  end

  def handle_set_bookmark(params, socket) do
    with id when is_binary(id) <- Map.get(params, "id"),
         value when value in ["true", "false"] <- Map.get(params, "bookmarked"),
         project_id when not is_nil(project_id) <- parse_int(id),
         {:ok, _project} <- Projects.set_bookmarked(project_id, value == "true") do
      {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
    else
      _ -> {:noreply, socket}
    end
  end

  # macOS-specific: uses osascript for folder picker. Intentionally not generalized.
  # Clicking "New project" triggers this. If the picker is cancelled or fails,
  # handle_pick_folder/2 falls through to the inline path input fallback.
  # NOTE: Creating a project does NOT auto-select it. Check the old Sidebar behavior —
  # if it auto-selected, add |> assign(:sidebar_project, project) to handle_pick_folder/2.
  def handle_show_new_project(socket) do
    {:noreply,
     start_async(socket, :pick_folder, fn ->
       System.cmd(
         "osascript",
         ["-e", ~s[POSIX path of (choose folder with prompt "Select project folder:")]],
         stderr_to_stdout: true
       )
     end)}
  end

  def handle_cancel_new_project(socket),
    do: {:noreply, assign(socket, :new_project_path, nil)}

  def handle_update_project_path(%{"value" => value}, socket),
    do: {:noreply, assign(socket, :new_project_path, value)}

  # Reads path from submit params first, falls back to assign.
  # This handles paste-then-submit before keyup fires.
  def handle_create_project(params, socket) do
    path =
      (params["path"] || socket.assigns.new_project_path || "")
      |> String.trim()

    if path != "" do
      name = path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path

      case Projects.create_project(%{name: name, path: path}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:projects, Projects.list_projects_for_sidebar())
           |> assign(:new_project_path, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :new_project_path, nil)}
      end
    else
      {:noreply, assign(socket, :new_project_path, nil)}
    end
  end

  def handle_new_session(%{"project_id" => project_id_str}, socket) do
    with project_id when not is_nil(project_id) <- parse_int(project_id_str),
         {:ok, project} <- Projects.get_project(project_id),
         {:ok, %{session: session}} <-
           EyeInTheSky.Agents.AgentManager.create_agent(
             project_id: project.id,
             project_path: project.path,
             model: "sonnet",
             eits_workflow: "0"
           ) do
      {:noreply, push_navigate(socket, to: "/dm/#{session.id}")}
    else
      nil -> {:noreply, socket}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Project not found")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create agent")}
    end
  end

  def handle_pick_folder({path, 0}, socket) do
    path = String.trim(path)
    name = path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path

    case Projects.create_project(%{name: name, path: path}) do
      {:ok, _} -> {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
      {:error, _} -> {:noreply, socket}
    end
  end

  # Cancelled or failed: show inline path input fallback
  def handle_pick_folder(_result, socket),
    do: {:noreply, assign(socket, :new_project_path, "")}

  # Only called when sidebar_project is nil (guarded in rail.ex handle_event clause).
  # Restores the project from a localStorage-persisted project_id after cross-LiveView nav.
  def handle_restore_project(id_str, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        case Projects.get_project(id) do
          {:ok, project} ->
            socket =
              socket
              |> assign(
                :sidebar_project,
                project
              )
              |> assign(
                :flyout_sessions,
                Loader.load_flyout_sessions(
                  project,
                  socket.assigns.session_sort,
                  socket.assigns.session_name_filter
                )
              )

            {:noreply, socket}

          {:error, _} ->
            # Project was deleted or inaccessible — clear the stale localStorage entry.
            {:noreply, push_event(socket, "save_project", %{project_id: nil})}
        end
    end
  end

  # Full select_project flow: delegates to handle_select_project/2 for the project
  # change, then reloads sessions + files and persists the selection to localStorage.
  def handle_select_project_with_reload(params, socket) do
    previous_project = socket.assigns.sidebar_project
    {:noreply, socket2} = handle_select_project(params, socket)
    new_project = socket2.assigns.sidebar_project

    socket3 =
      if new_project != previous_project do
        socket2
        |> assign(
          :flyout_sessions,
          Loader.load_flyout_sessions(
            new_project,
            socket2.assigns.session_sort,
            socket2.assigns.session_name_filter
          )
        )
        |> assign(:flyout_file_expanded, MapSet.new())
        |> assign(:flyout_file_children, %{})
        |> Loader.maybe_load_files(socket2.assigns.active_section)
      else
        socket2
      end

    project_id = new_project && new_project.id
    socket4 = push_event(socket3, "save_project", %{project_id: project_id})
    {:noreply, socket4 |> assign(:proj_picker_open, false) |> assign(:scope_type, :project)}
  end

  def handle_select_workspace(socket) do
    {:noreply,
     socket
     |> assign(:proj_picker_open, false)
     |> assign(:sidebar_project, nil)
     |> assign(:scope_type, :workspace)
     |> push_navigate(to: "/workspace/sessions")}
  end
end

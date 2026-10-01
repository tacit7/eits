defmodule EyeInTheSkyWeb.Components.Rail.ProjectActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, push_event: 3, put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Settings
  alias EyeInTheSky.Workspaces
  alias EyeInTheSkyWeb.Components.Rail.Loader
  alias EyeInTheSkyWeb.Helpers.ViewHelpers

  def handle_start_rename(%{"project_id" => id_str}, socket) do
    with id when not is_nil(id) <- parse_int(id_str),
         {:ok, project} <- Projects.get_project(id) do
      {:noreply, assign(socket, renaming_project_id: id, rename_value: project.name)}
    else
      _ -> {:noreply, socket}
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
        {:error, _} ->
          # Project deleted while rename UI was open — reload to clear stale entry.
          {:noreply,
           socket
           |> put_flash(:error, "Project not found")
           |> assign(:projects, workspace_projects(socket))
           |> assign(:renaming_project_id, nil)
           |> assign(:rename_value, "")}

        {:ok, project} ->
          case Projects.update_project(project, %{name: name}) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:projects, workspace_projects(socket))
               |> assign(:renaming_project_id, nil)
               |> assign(:rename_value, "")}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to rename project")
               |> assign(:projects, workspace_projects(socket))
               |> assign(:renaming_project_id, nil)
               |> assign(:rename_value, "")}
          end
      end
    end
  end

  def handle_delete_project(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        case Projects.get_project(id) do
          {:ok, project} ->
            case Projects.delete_project(project) do
              {:ok, _} ->
                {:noreply, assign(socket, :projects, workspace_projects(socket))}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to delete project")}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Project not found")}
        end
    end
  end

  # Context-menu rename: name comes from the ctx-menu's own prompt dialog, so
  # this is a direct rename with no dependency on renaming_project_id/
  # rename_value (those back an inline-edit UI no template currently renders).
  def handle_rename_project(%{"project_id" => id_str, "name" => name}, socket)
      when is_binary(name) do
    trimmed = String.trim(name)

    with id when not is_nil(id) <- parse_int(id_str),
         true <- trimmed != "",
         {:ok, project} <- Projects.get_project(id),
         {:ok, _} <- Projects.update_project(project, %{name: trimmed}) do
      {:noreply, assign(socket, :projects, workspace_projects(socket))}
    else
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Project not found")}
      _ -> {:noreply, socket}
    end
  end

  def handle_rename_project(_params, socket), do: {:noreply, socket}

  @doc """
  Opens a terminal window cd'd into the project's path. Path comes from the
  DB, never from the client — same trust boundary as handle_open_worktree.
  """
  def handle_open_terminal(%{"project_id" => id_str}, socket) do
    with id when not is_nil(id) <- parse_int(id_str),
         {:ok, project} <- Projects.get_project(id),
         path when is_binary(path) and path != "" <- project.path,
         true <- File.dir?(path) do
      open_terminal_at(path)
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "No path to open a terminal in")}
    end
  end

  defp open_terminal_at(path) do
    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", ["-a", "Terminal", path])
      {:win32, _} -> System.cmd("cmd", ["/c", "start", "cmd", "/K", "cd", "/d", path])
      _ -> System.cmd("x-terminal-emulator", [], cd: path)
    end
  end

  @doc """
  Opens the project's path in the user's preferred external editor
  (`EyeInTheSky.Editors`). Path comes from the DB, never from the client.
  """
  def handle_open_in_editor(%{"project_id" => id_str}, socket) do
    with id when not is_nil(id) <- parse_int(id_str),
         {:ok, project} <- Projects.get_project(id),
         path when is_binary(path) and path != "" <- project.path do
      editor = Settings.get("preferred_editor") || "code"
      ViewHelpers.handle_open_in_editor(path, editor, socket)
    else
      _ -> {:noreply, put_flash(socket, :error, "No path to open in an editor")}
    end
  end

  def handle_set_bookmark(params, socket) do
    with id when is_binary(id) <- Map.get(params, "id"),
         value when value in ["true", "false"] <- Map.get(params, "bookmarked"),
         project_id when not is_nil(project_id) <- parse_int(id),
         {:ok, _project} <- Projects.set_bookmarked(project_id, value == "true") do
      {:noreply, assign(socket, :projects, workspace_projects(socket))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_new_session(%{"project_id" => project_id_str}, socket) do
    with project_id when not is_nil(project_id) <- parse_int(project_id_str),
         {:ok, project} <- Projects.get_project(project_id),
         {:ok, %{session: session}} <-
           AgentManager.create_agent(
             project_id: project.id,
             project_path: project.path,
             model: Settings.default_model(),
             eits_workflow: "0"
           ) do
      {:noreply, push_navigate(socket, to: "/dm/#{session.id}")}
    else
      nil -> {:noreply, socket}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Project not found")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create agent")}
    end
  end

  def handle_new_session_navigate(%{"project_id" => project_id}, socket) do
    if EyeInTheSky.Settings.get_boolean("dm_use_pty") do
      handle_new_session(%{"project_id" => project_id}, socket)
    else
      {:noreply, push_navigate(socket, to: "/dm/new?project_id=#{project_id}")}
    end
  end

  defp current_workspace_id(socket) do
    socket.assigns[:workspace_id] ||
      get_in(socket.assigns, [:workspace, Access.key(:id)]) ||
      get_in(socket.assigns, [:sidebar_project, Access.key(:workspace_id)])
  end

  defp workspace_projects(_socket) do
    Projects.list_projects_for_sidebar()
  end

  defp select_project(socket, project) do
    workspace = Workspaces.get_workspace(project.workspace_id)

    socket
    |> assign(:sidebar_project, project)
    |> assign(:workspace, workspace)
    |> assign(:workspace_id, workspace && workspace.id)
    |> assign(:projects, Projects.list_projects_for_sidebar())
  end

  # Opens the given project in a new Tauri window. No-op in browser context
  # (the JS bridge guard prevents the invoke call from running).
  def handle_open_in_window(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        case Projects.get_project(id) do
          {:ok, _project} ->
            {:noreply, push_event(socket, "open_in_window", %{path: "/projects/#{id}"})}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # Only called when sidebar_project is nil (guarded in rail.ex handle_event clause).
  # Restores the project from a localStorage-persisted project_id after cross-LiveView nav.
  def handle_restore_project(id_str, socket) do
    current_id = get_in(socket.assigns, [:sidebar_project, Access.key(:id)])
    workspace_id = current_workspace_id(socket)

    case parse_int(id_str) do
      nil ->
        {:noreply, persist_selected_project(socket, current_id)}

      id ->
        case Projects.get_project(id) do
          {:ok, project} when not is_nil(workspace_id) and project.workspace_id == workspace_id ->
            {:noreply,
             socket
             |> restore_project(project)
             |> persist_selected_project(project.id)}

          {:error, _} ->
            {:noreply, fallback_restored_project(socket, current_id)}

          {:ok, _foreign} ->
            {:noreply, fallback_restored_project(socket, current_id)}
        end
    end
  end

  defp restore_project(socket, project) do
    socket
    |> select_project(project)
    |> assign(
      :flyout_sessions,
      Loader.load_flyout_sessions(
        project,
        socket.assigns.session_sort,
        socket.assigns.session_name_filter
      )
    )
  end

  defp fallback_restored_project(socket, current_id) when not is_nil(current_id) do
    socket
    |> assign(:projects, workspace_projects(socket))
    |> persist_selected_project(current_id)
  end

  defp fallback_restored_project(socket, _current_id) do
    case workspace_projects(socket) do
      [project | _] ->
        socket
        |> restore_project(project)
        |> persist_selected_project(project.id)

      [] ->
        persist_selected_project(socket, nil)
    end
  end

  defp persist_selected_project(socket, project_id) do
    push_event(socket, "save_rail_state", %{project_id: project_id})
  end

  # Maps the current sidebar_tab to the equivalent project-scoped route.
  # Returns nil for global tabs (:usage, :chat, :canvas, :notifications, :dm)
  # so the caller can skip navigation and leave the user on their current page.
  def project_path(id, tab) do
    case tab do
      :sessions -> "/projects/#{id}/sessions"
      :tasks -> "/projects/#{id}/tasks"
      :kanban -> "/projects/#{id}/kanban"
      :notes -> "/projects/#{id}/notes"
      :prompts -> "/projects/#{id}/prompts"
      :skills -> "/projects/#{id}/skills"
      :teams -> "/projects/#{id}/teams"
      :agents -> "/projects/#{id}/agents"
      :files -> "/projects/#{id}/files"
      :jobs -> "/projects/#{id}/jobs"
      :config -> "/projects/#{id}/config"
      _ -> nil
    end
  end
end

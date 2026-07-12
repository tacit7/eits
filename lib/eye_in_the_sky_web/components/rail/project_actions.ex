defmodule EyeInTheSkyWeb.Components.Rail.ProjectActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, push_event: 3, put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Components.Rail.Loader
  alias EyeInTheSkyWeb.Helpers.ViewHelpers

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
           |> assign(:projects, Projects.list_projects_for_sidebar())
           |> assign(:renaming_project_id, nil)
           |> assign(:rename_value, "")}

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
              {:ok, _} -> {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
              {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete project")}
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
      {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
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
      {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
    else
      _ -> {:noreply, socket}
    end
  end

  # Pushes a phx:pick_folder event to the client.
  # In Tauri: JS invokes the native folder picker (Rust pick_folder command) and
  # pushes folder_picked back. In the browser: JS immediately pushes folder_picked
  # with an empty payload to show the inline text-input fallback.
  # NOTE: Creating a project does NOT auto-select it.
  def handle_show_new_project(socket) do
    {:noreply, push_event(socket, "pick_folder", %{})}
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
      name = basename_from_path(path)

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

  # Called by handle_event("folder_picked") in rail.ex — payload comes from the
  # Tauri pick_folder JS bridge after the user selects a folder.
  # If the path already exists as a project, switch to it rather than failing silently.
  # path absent or empty → falls through to the inline text-input fallback clause below.
  def handle_folder_picked(%{"path" => path}, socket) when is_binary(path) and path != "" do
    path = String.trim(path)
    name = basename_from_path(path)

    case Projects.create_project(%{name: name, path: path}) do
      {:ok, _} ->
        {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}

      {:error, changeset} ->
        if path_taken?(changeset) do
          # Path already exists — select the existing project and tell the user.
          case Projects.get_project_by_path(path) do
            {:ok, project} ->
              {:noreply,
               socket
               |> put_flash(:info, "\"#{project.name}\" is already in your projects")
               |> assign(:projects, Projects.list_projects_for_sidebar())
               |> assign(:sidebar_project, project)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not add project at #{path}")}
          end
        else
          # Surface the failure — a silent {:noreply, socket} here cost multiple
          # debugging rounds (nothing appears in the UI and nothing is logged).
          errors =
            changeset.errors
            |> Enum.map_join(", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)

          {:noreply, put_flash(socket, :error, "Could not add project: #{errors}")}
        end
    end
  end

  # Empty payload = cancelled or no Tauri; show the inline text-input fallback.
  def handle_folder_picked(_params, socket),
    do: {:noreply, assign(socket, :new_project_path, "")}

  defp basename_from_path(path) do
    path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path
  end

  defp path_taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:path, {_, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
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
            {:noreply, push_event(socket, "save_rail_state", %{project_id: nil})}
        end
    end
  end

  # Full select_project flow: delegates to handle_select_project/2 for the project
  # change, then reloads sessions + files, persists the selection to localStorage,
  # and navigates to the equivalent route on the new project.
  def handle_select_project_with_reload(params, socket) do
    previous_project = socket.assigns.sidebar_project
    {:noreply, socket} = handle_select_project(params, socket)
    new_project = socket.assigns.sidebar_project

    socket =
      if new_project != previous_project do
        socket
        |> assign(
          :flyout_sessions,
          Loader.load_flyout_sessions(
            new_project,
            socket.assigns.session_sort,
            socket.assigns.session_name_filter
          )
        )
        |> assign(:flyout_file_expanded, MapSet.new())
        |> assign(:flyout_file_children, %{})
        |> Loader.maybe_load_files(socket.assigns.active_section)
      else
        socket
      end

    project_id = new_project && new_project.id

    socket =
      socket
      |> push_event("save_rail_state", %{project_id: project_id})
      |> assign(:proj_picker_open, false)
      |> assign(:scope_type, :project)

    # Navigate to the equivalent route on the newly selected project, preserving
    # the current tab context (sessions, tasks, notes, etc.).
    # Global tabs (:usage, :chat, :canvas, :notifications, :dm) return nil from
    # project_path/2 — in that case skip navigation and stay on the current page.
    socket =
      if not is_nil(new_project) and new_project != previous_project do
        sidebar_tab = socket.assigns[:sidebar_tab] || :sessions
        case project_path(new_project.id, sidebar_tab) do
          nil -> socket
          path -> push_navigate(socket, to: path)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  # Maps the current sidebar_tab to the equivalent project-scoped route.
  # Returns nil for global tabs (:usage, :chat, :canvas, :notifications, :dm)
  # so the caller can skip navigation and leave the user on their current page.
  defp project_path(id, tab) do
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

  def handle_select_workspace(socket) do
    {:noreply,
     socket
     |> assign(:proj_picker_open, false)
     |> assign(:sidebar_project, nil)
     |> assign(:scope_type, :workspace)
     |> push_navigate(to: "/workspace/sessions")}
  end
end

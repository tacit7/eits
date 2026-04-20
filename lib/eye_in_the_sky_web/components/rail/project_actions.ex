defmodule EyeInTheSkyWeb.Components.Rail.ProjectActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, push_navigate: 2, put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.{Events, Projects}

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

    if name != "" && not is_nil(socket.assigns.renaming_project_id) do
      case Projects.get_project(socket.assigns.renaming_project_id) do
        {:ok, project} -> Projects.update_project(project, %{name: name})
        {:error, _} -> :ok
      end
    end

    {:noreply,
     socket
     |> assign(:projects, Projects.list_projects_for_sidebar())
     |> assign(:renaming_project_id, nil)
     |> assign(:rename_value, "")}
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
         {:ok, project} <- Projects.set_bookmarked(project_id, value == "true") do
      Events.project_updated(project)
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
end

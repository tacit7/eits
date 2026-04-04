defmodule EyeInTheSkyWeb.Components.Sidebar.ProjectActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, push_navigate: 2]

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.{Projects, Events}
  alias EyeInTheSky.Agents.AgentManager

  def handle_select_project(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        current_id = get_in(socket.assigns, [:sidebar_project, Access.key(:id)])

        if current_id == id do
          {:noreply, assign(socket, :sidebar_project, nil)}
        else
          {:noreply, assign(socket, :sidebar_project, Projects.get_project!(id))}
        end
    end
  end

  def handle_start_rename(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        project = Projects.get_project!(id)
        {:noreply, assign(socket, renaming_project_id: id, rename_value: project.name)}
    end
  end

  def handle_cancel_rename(socket) do
    {:noreply, assign(socket, renaming_project_id: nil, rename_value: "")}
  end

  def handle_update_rename_value(%{"value" => value}, socket) do
    {:noreply, assign(socket, :rename_value, value)}
  end

  def handle_commit_rename(socket) do
    name = String.trim(socket.assigns.rename_value)

    if name != "" && socket.assigns.renaming_project_id do
      project = Projects.get_project!(socket.assigns.renaming_project_id)
      Projects.update_project(project, %{name: name})
    end

    {:noreply,
     socket
     |> assign(:projects, Projects.list_projects_for_sidebar())
     |> assign(:renaming_project_id, nil)
     |> assign(:rename_value, "")}
  end

  def handle_delete_project(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        Projects.get_project!(id) |> Projects.delete_project()
        {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
    end
  end

  def handle_set_bookmark(params, socket) do
    with id when is_binary(id) <- Map.get(params, "id"),
         value when value in ["true", "false"] <- Map.get(params, "bookmarked"),
         {project_id, ""} <- Integer.parse(id),
         {:ok, project} <- Projects.set_bookmarked(project_id, value == "true") do
      Events.project_updated(project)
      {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
    else
      _ -> {:noreply, socket}
    end
  end

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

  def handle_cancel_new_project(socket) do
    {:noreply, assign(socket, :new_project_path, nil)}
  end

  def handle_update_project_path(%{"value" => value}, socket) do
    {:noreply, assign(socket, :new_project_path, value)}
  end

  def handle_create_project(socket) do
    path = (socket.assigns.new_project_path || "") |> String.trim()

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
    with {project_id, ""} <- Integer.parse(project_id_str),
         project <- Projects.get_project!(project_id),
         {:ok, %{session: session}} <-
           AgentManager.create_agent(
             project_id: project.id,
             project_path: project.path,
             model: "sonnet",
             eits_workflow: "0"
           ) do
      {:noreply, push_navigate(socket, to: "/dm/#{session.id}")}
    else
      _ -> {:noreply, socket}
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

  def handle_pick_folder(_result, socket) do
    {:noreply, assign(socket, :new_project_path, "")}
  end
end

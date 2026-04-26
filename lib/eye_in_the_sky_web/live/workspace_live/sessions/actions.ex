defmodule EyeInTheSkyWeb.WorkspaceLive.Sessions.Actions do
  @moduledoc """
  Session creation action for the workspace sessions LiveView.

  The key difference from ProjectLive.Sessions.Actions: project_id comes from
  form params (user selected it from the workspace project dropdown), not from
  socket.assigns.project.
  """

  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, stream_insert: 4]
  import EyeInTheSkyWeb.Helpers.AgentCreationHelpers, only: [build_opts: 2]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Repo
  alias EyeInTheSkyWeb.ControllerHelpers

  def create_new_session(params, socket) do
    workspace_id = socket.assigns.workspace.id

    case ControllerHelpers.parse_int(params["project_id"]) do
      nil ->
        {:noreply, put_flash(socket, :error, "Please select a project")}

      project_id ->
        case Projects.get_project(project_id) do
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Project not found")}

          {:ok, %{workspace_id: ^workspace_id} = project} ->
            do_create(params, project, socket)

          {:ok, _project} ->
            {:noreply, put_flash(socket, :error, "Project not found")}
        end
    end
  end

  defp do_create(params, project, socket) do
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    opts =
      build_opts(params,
        project_path: project.path,
        description: agent_name,
        instructions: description
      )
      |> Keyword.put(:project_id, project.id)

    case AgentManager.create_agent(opts) do
      {:ok, %{session: session}} ->
        session = Repo.preload(session, :project)

        socket =
          socket
          |> assign(:show_new_session_drawer, false)
          |> stream_insert(:session_list, session, at: 0)
          |> put_flash(:info, "Session launched")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("WorkspaceLive create_new_session failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to launch session")}
    end
  end
end

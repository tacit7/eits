defmodule EyeInTheSkyWeb.WorkspaceLive.Sessions.Actions do
  @moduledoc """
  Session creation action for the workspace sessions LiveView.

  The key difference from ProjectLive.Sessions.Actions: project_id comes from
  form params (user selected it from the workspace project dropdown), not from
  socket.assigns.project.
  """

  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.Helpers.AgentCreationHelpers, only: [build_opts: 2]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Projects
  alias EyeInTheSkyWeb.ControllerHelpers

  def create_new_session(params, socket) do
    project_id = ControllerHelpers.parse_int(params["project_id"])

    with true <- is_integer(project_id),
         {:ok, project} <- Projects.get_project(project_id) do
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
        {:ok, _result} ->
          socket =
            socket
            |> assign(:show_new_session_drawer, false)
            |> put_flash(:info, "Session launched")

          {:noreply, socket}

        {:error, reason} ->
          Logger.error("WorkspaceLive create_new_session failed: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
      end
    else
      false ->
        {:noreply, put_flash(socket, :error, "Please select a project")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Project not found")}
    end
  end
end

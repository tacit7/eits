defmodule EyeInTheSkyWebWeb.DmLive.TaskHandlers do
  @moduledoc """
  DM-specific task event handlers that depend on session/agent context.

  These handlers are extracted from DmLive because they depend on agent
  spawning infrastructure (AgentManager, SessionHelpers) that is not
  appropriate to pull into the general-purpose TasksHelpers.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWeb.Agents.AgentManager
  alias EyeInTheSkyWebWeb.Live.Shared.SessionHelpers

  @doc """
  Spawns a new agent session pre-loaded with the given task's title and
  description as its initial prompt. Links the new session to the task.

  Requires assigns: `:session`, `:agent`
  """
  def handle_start_agent_for_task(%{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    session = socket.assigns.session
    agent = socket.assigns.agent

    project_id = agent.project_id

    project_path =
      case SessionHelpers.resolve_project_path(session, agent) do
        {:ok, path} -> path
        _ -> nil
      end

    task_prompt = "#{task.title}\n\n#{task.description || ""}" |> String.trim()

    opts =
      [description: task.title, instructions: task_prompt, model: "sonnet"]
      |> then(fn o -> if project_id, do: o ++ [project_id: project_id], else: o end)
      |> then(fn o -> if project_path, do: o ++ [project_path: project_path], else: o end)

    case AgentManager.create_agent(opts) do
      {:ok, %{session: new_session}} ->
        Tasks.link_session_to_task(task.id, new_session.id)

        {:noreply,
         socket
         |> assign(:active_overlay, nil)
         |> put_flash(:info, "Agent spawned for: #{String.slice(task.title, 0..40)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to spawn agent: #{inspect(reason)}")}
    end
  end
end

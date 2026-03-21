defmodule EyeInTheSkyWeb.Live.Shared.AgentHelpers do
  @moduledoc """
  Shared helper for spawning agents from task context.
  Import in any LiveView that needs start_agent_for_task functionality.
  """

  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias EyeInTheSky.Tasks
  alias EyeInTheSky.Agents.AgentManager

  @doc """
  Spawns an agent for the given task and links the resulting session.
  Returns `{:noreply, socket}`.
  """
  def handle_start_agent_for_task(%{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    project = socket.assigns.project

    task_prompt = "#{task.title}\n\n#{task.description || ""}" |> String.trim()

    opts = [
      description: task.title,
      instructions: task_prompt,
      project_id: project.id,
      project_path: project.path,
      model: "sonnet"
    ]

    case AgentManager.create_agent(opts) do
      {:ok, %{session: session}} ->
        Tasks.link_session_to_task(task.id, session.id)

        socket =
          socket
          |> assign(:show_task_detail_drawer, false)
          |> put_flash(:info, "Agent spawned for task: #{String.slice(task.title, 0..40)}")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to spawn agent: #{inspect(reason)}")}
    end
  end
end

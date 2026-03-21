defmodule EyeInTheSkyWeb.DmLive.AgentLifecycle do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.DmLive.MessageHandlers
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers

  require Logger

  def handle_claude_response(session_ref, response, socket) do
    Logger.info(
      "Claude response received ref=#{inspect(session_ref)} type=#{inspect(response["type"])}"
    )

    socket =
      socket
      |> assign(:processing, false)
      |> MessageHandlers.sync_and_reload()
      |> push_event("focus-input", %{})

    {:noreply, socket}
  end

  def handle_claude_complete(session_ref, exit_code, socket) do
    Logger.info("Claude session completed ref=#{inspect(session_ref)} exit=#{exit_code}")

    socket =
      socket
      |> assign(:processing, false)
      |> assign(:session_ref, nil)
      |> MessageHandlers.sync_and_reload()
      |> push_event("focus-input", %{})

    {:noreply, socket}
  end

  def handle_agent_working(msg, socket) do
    AgentStatusHelpers.handle_agent_working_if_match(
      socket,
      msg,
      :session_id,
      fn socket, _session_id ->
        case msg do
          %{status: "compacting"} ->
            assign(socket, :compacting, true)

          _other ->
            socket
            |> assign(:compacting, false)
            |> assign(:processing, true)
        end
      end
    )
  end

  def handle_agent_stopped(msg, socket) do
    AgentStatusHelpers.handle_agent_stopped_if_match(
      socket,
      msg,
      :session_id,
      fn socket, _session_id ->
        socket
        |> assign(:compacting, false)
        |> assign(:processing, false)
        |> MessageHandlers.sync_and_reload()
        |> push_event("focus-input", %{})
      end
    )
  end

  def handle_agent_updated(%{id: session_id} = updated_session, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply, assign(socket, :session, updated_session)}
    else
      {:noreply, socket}
    end
  end

  def handle_tasks_changed(socket) do
    {:noreply,
     assign(socket, :current_task, Tasks.get_current_task_for_session(socket.assigns.session_id))}
  end
end

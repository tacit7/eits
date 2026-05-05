defmodule EyeInTheSkyWeb.DmLive.AgentLifecycle do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias EyeInTheSky.Desktop
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
        maybe_notify_desktop_on_stop(socket)

        socket
        |> assign(:compacting, false)
        |> assign(:processing, false)
        |> MessageHandlers.sync_and_reload()
        |> push_event("focus-input", %{})
      end
    )
  end

  defp maybe_notify_desktop_on_stop(socket) do
    notify? = Map.get(socket.assigns, :notify_on_stop, false)
    desktop? = Desktop.desktop_mode?()

    Logger.info("agent_stopped notify check: notify_on_stop=#{notify?} desktop_mode?=#{desktop?}")

    if notify? && desktop? do
      session = socket.assigns[:session]
      title = (session && session.name) || "EITS"
      Logger.info("Firing Desktop.notify(\"Session stopped\", #{inspect(title)})")
      Desktop.notify("Session stopped", title)
    end

    :ok
  end

  def handle_agent_updated(%{id: session_id} = updated_session, socket) do
    if session_id == socket.assigns.session_id do
      socket =
        socket
        |> assign(:session, updated_session)
        |> assign(:session_status, updated_session.status)
        |> sync_processing_from_status(updated_session.status)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Sync processing/compacting assigns from session status as a fallback.
  # The agent_stopped PubSub event is the primary mechanism, but hook delivery
  # issues can cause misses. The session_updated broadcast always fires and
  # carries the authoritative status.
  defp sync_processing_from_status(socket, "working") do
    socket |> assign(:compacting, false) |> assign(:processing, true)
  end

  defp sync_processing_from_status(socket, "compacting") do
    assign(socket, :compacting, true)
  end

  defp sync_processing_from_status(socket, status)
       when status in ["idle", "waiting", "completed", "failed", "error"] do
    socket |> assign(:compacting, false) |> assign(:processing, false)
  end

  defp sync_processing_from_status(socket, _status), do: socket

  def handle_tasks_changed(socket) do
    {:noreply,
     assign(socket, :current_task, Tasks.get_current_task_for_session(socket.assigns.session_id))}
  end
end

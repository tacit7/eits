defmodule EyeInTheSkyWeb.Live.Shared.DmSessionHelpers do
  @moduledoc false
  require Logger

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Notes, Sessions}

  def handle_update_session_name(%{"value" => value}, socket) do
    session = socket.assigns.session
    value = String.trim(value)
    name = if(value == "", do: nil, else: value)

    case Sessions.update_session(session, %{name: name}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:session, updated)
         |> assign(:page_title, updated.name || "Session")}

      {:error, changeset} ->
        Logger.error("Failed to update session name: #{inspect(changeset.errors)}")
        {:noreply, put_flash(socket, :error, "Failed to update session name")}
    end
  end

  def handle_update_session_description(%{"value" => value}, socket) do
    session = socket.assigns.session
    value = String.trim(value)

    case Sessions.update_session(session, %{description: if(value == "", do: nil, else: value)}) do
      {:ok, updated} ->
        {:noreply, assign(socket, :session, updated)}

      {:error, changeset} ->
        Logger.error("Failed to update session description: #{inspect(changeset.errors)}")
        {:noreply, put_flash(socket, :error, "Failed to update session description")}
    end
  end

  def handle_toggle_star(params, socket, load_notes_fn) do
    note_id = params["note_id"] || params["note-id"] || params["value"]

    case Notes.toggle_starred(note_id) do
      {:ok, _note} ->
        {:noreply, load_notes_fn.(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle star")}
    end
  end

  def handle_kill_session(socket) do
    session_id = socket.assigns.session_id

    # Properly stop the worker — GenServer.stop calls terminate/2 which cancels the SDK subprocess.
    # Process.exit does NOT call terminate/2 for non-trapping GenServers, so the CLI keeps running.
    case Registry.lookup(EyeInTheSky.Claude.AgentRegistry, {:session, session_id}) do
      [{pid, _}] ->
        Logger.warning(
          "kill_session: stopping worker pid=#{inspect(pid)} for session=#{session_id}"
        )

        try do
          GenServer.stop(pid, :shutdown, 3000)
        catch
          :exit, _ -> :ok
        end

      [] ->
        AgentManager.cancel_session(session_id)
    end

    # Update session status so stale agent_working PubSub events don't revive the UI
    case Sessions.get_session(session_id) do
      {:ok, session} ->
        Sessions.set_session_idle(session)

      _ ->
        :ok
    end

    {:noreply, assign(socket, :processing, false)}
  end
end

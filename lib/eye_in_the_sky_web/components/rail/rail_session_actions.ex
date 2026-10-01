defmodule EyeInTheSkyWeb.Components.Rail.RailSessionActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.{Channels, Events}
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.AgentLive.IndexActions
  alias EyeInTheSkyWeb.Components.Rail.Loader

  def handle_toggle_new_session_drawer(params, socket) do
    _ = params
    {:noreply, assign(socket, :show_new_session_form, !socket.assigns.show_new_session_form)}
  end

  def handle_toggle_new_channel_form(params, socket) do
    _ = params
    {:noreply, assign(socket, :show_new_channel_form, !socket.assigns.show_new_channel_form)}
  end

  def handle_open_new_session_with_agent(%{"slug" => slug, "name" => name}, socket) do
    {:noreply,
     socket
     |> assign(:show_new_session_form, true)
     |> assign(:prefill_agent_slug, slug)
     |> assign(:prefill_agent_name, name)}
  end

  def handle_create_new_session(params, socket) do
    socket =
      socket
      |> assign(:show_new_session_form, false)
      |> assign(:prefill_agent_slug, nil)
      |> assign(:prefill_agent_name, nil)

    case params["submit_action"] do
      "chat" -> IndexActions.handle_create_new_session(params, socket)
      _ -> IndexActions.handle_launch_new_session(params, socket)
    end
  end

  def handle_create_channel(params, socket) do
    name = String.trim(params["channel_name"] || "")

    cond do
      name == "" ->
        {:noreply, put_flash(socket, :error, "Channel name is required")}

      String.length(name) > 80 ->
        {:noreply, put_flash(socket, :error, "Channel name must be 80 characters or fewer")}

      true ->
        project_id = socket.assigns.sidebar_project && socket.assigns.sidebar_project.id

        case Channels.create_channel(%{
               name: name,
               channel_type: "public",
               project_id: project_id
             }) do
          {:ok, channel} ->
            Events.channel_created(channel)

            socket =
              socket
              |> assign(:show_new_channel_form, false)
              |> assign(
                :flyout_channels,
                Loader.load_flyout_channels(socket.assigns.sidebar_project)
              )

            {:noreply, put_flash(socket, :info, "Channel ##{channel.name} created")}

          {:error, %Ecto.Changeset{errors: [name: {msg, _}]}} ->
            {:noreply, put_flash(socket, :error, "Channel name #{msg}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create channel")}
        end
    end
  end

  def handle_delete_channel(%{"channel_id" => channel_id}, socket) do
    case Channels.get_channel(channel_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Channel not found")}

      channel ->
        case Channels.update_channel(channel, %{archived_at: DateTime.utc_now()}) do
          {:ok, updated} ->
            Events.channel_deleted(updated)

            socket =
              assign(
                socket,
                :flyout_channels,
                Loader.load_flyout_channels(socket.assigns.sidebar_project)
              )

            {:noreply, put_flash(socket, :info, "Channel ##{channel.name} deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete ##{channel.name}")}
        end
    end
  end

  # Context-menu rename: name comes from the ctx-menu's own prompt dialog.
  def handle_rename_channel(%{"channel_id" => channel_id, "name" => name}, socket)
      when is_binary(name) do
    trimmed = String.trim(name)

    case {trimmed, Channels.get_channel(channel_id)} do
      {"", _} ->
        {:noreply, socket}

      {_, nil} ->
        {:noreply, put_flash(socket, :error, "Channel not found")}

      {_, channel} ->
        case Channels.update_channel(channel, %{name: trimmed}) do
          {:ok, _} ->
            {:noreply,
             assign(
               socket,
               :flyout_channels,
               Loader.load_flyout_channels(socket.assigns.sidebar_project)
             )}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to rename channel")}
        end
    end
  end

  def handle_rename_channel(_params, socket), do: {:noreply, socket}

  def handle_archive_session(%{"session_id" => session_id_str}, socket) do
    case parse_int(session_id_str) do
      nil ->
        {:noreply, socket}

      session_id ->
        case Sessions.get_session(session_id) do
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Session not found")}

          {:ok, session} ->
            case Sessions.archive_session(session) do
              {:ok, _} ->
                socket =
                  socket
                  |> reload_flyout_sessions()
                  |> put_flash(:info, "Session archived")

                {:noreply, socket}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not archive session")}
            end
        end
    end
  end

  @doc """
  Reveals a session's worktree in the OS file manager. The Phoenix server
  always runs on the user's machine in this architecture (dev server or the
  desktop app's embedded release), so a server-side `open` works for BOTH
  web and desktop — no Tauri command needed. Path comes from the DB, never
  from the client.
  """
  def handle_open_worktree(%{"session_id" => session_id_str}, socket) do
    with session_id when not is_nil(session_id) <- parse_int(session_id_str),
         {:ok, session} <- Sessions.get_session(session_id),
         path when is_binary(path) and path != "" <- session.git_worktree_path,
         true <- File.dir?(path) do
      System.cmd(reveal_cmd(), [path])
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "No worktree to open for this session")}
    end
  end

  defp reveal_cmd do
    case :os.type() do
      {:unix, :darwin} -> "open"
      {:win32, _} -> "explorer"
      _ -> "xdg-open"
    end
  end

  def handle_rename_session(%{"session_id" => session_id_str, "name" => name}, socket)
      when is_binary(name) and name != "" do
    case parse_int(session_id_str) do
      nil ->
        {:noreply, socket}

      session_id ->
        case Sessions.get_session(session_id) do
          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Session not found")}

          {:ok, session} ->
            case Sessions.update_session(session, %{name: String.trim(name)}) do
              {:ok, _} ->
                socket = reload_flyout_sessions(socket)

                {:noreply, socket}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not rename session")}
            end
        end
    end
  end

  def handle_rename_session(_params, socket), do: {:noreply, socket}

  defp reload_flyout_sessions(socket) do
    assign(
      socket,
      :flyout_sessions,
      Loader.load_flyout_sessions(
        socket.assigns.sidebar_project,
        socket.assigns.session_sort,
        socket.assigns.session_name_filter,
        socket.assigns.session_show
      )
    )
  end
end

defmodule EyeInTheSkyWeb.Components.Rail.RailSessionActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSky.{Channels, Events}
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
end

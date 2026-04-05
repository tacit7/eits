defmodule EyeInTheSkyWeb.Components.Sidebar.ChannelActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.Channels
  alias EyeInTheSky.Channels.Channel

  def handle_show_new_channel(socket) do
    {:noreply, assign(socket, :new_channel_name, "")}
  end

  def handle_cancel_new_channel(socket) do
    {:noreply, assign(socket, :new_channel_name, nil)}
  end

  def handle_update_channel_name(%{"value" => value}, socket) do
    {:noreply, assign(socket, :new_channel_name, value)}
  end

  def handle_create_channel(socket) do
    name = (socket.assigns.new_channel_name || "") |> String.trim()

    if name != "" do
      project_id = get_in(socket.assigns, [:sidebar_project, Access.key(:id)]) || 1
      channel_id = Channel.generate_id(project_id, name)

      case Channels.create_channel(%{
             id: channel_id,
             uuid: Ecto.UUID.generate(),
             name: name,
             channel_type: "public",
             project_id: project_id
           }) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:channels, fetch_channels())
           |> assign(:new_channel_name, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :new_channel_name, nil)}
      end
    else
      {:noreply, assign(socket, :new_channel_name, nil)}
    end
  end

  defp fetch_channels do
    case Channels.list_channels() do
      channels when is_list(channels) -> channels
      _ -> []
    end
  end
end

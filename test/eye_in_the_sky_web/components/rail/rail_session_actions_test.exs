defmodule EyeInTheSkyWeb.Components.Rail.RailSessionActionsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Channels, Projects}
  alias EyeInTheSky.Channels.Channel
  alias EyeInTheSkyWeb.Components.Rail.RailSessionActions

  defp uniq, do: System.unique_integer([:positive])

  defp build_socket(assigns) do
    base = %{
      flash: %{},
      sidebar_project: nil,
      flyout_channels: [],
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns), private: %{live_temp: %{}}}
  end

  defp create_channel do
    {:ok, project} =
      Projects.create_project(%{
        name: "RailSessionActions project #{uniq()}",
        path: "/tmp/rsa-test-#{uniq()}",
        slug: "rsa-test-#{uniq()}"
      })

    channel_id = Channel.generate_id(project.id, "general-#{uniq()}")

    {:ok, channel} =
      Channels.create_channel(%{
        id: channel_id,
        uuid: Ecto.UUID.generate(),
        name: "general",
        channel_type: "public",
        project_id: project.id
      })

    channel
  end

  describe "handle_rename_channel/2" do
    test "renames the channel and refreshes flyout_channels" do
      channel = create_channel()
      socket = build_socket(%{})

      {:noreply, result} =
        RailSessionActions.handle_rename_channel(
          %{"channel_id" => channel.id, "name" => "renamed"},
          socket
        )

      reloaded = Channels.get_channel(channel.id)
      assert reloaded.name == "renamed"
      assert is_list(result.assigns.flyout_channels)
    end

    test "ignores a blank name" do
      channel = create_channel()
      socket = build_socket(%{})

      {:noreply, _result} =
        RailSessionActions.handle_rename_channel(%{"channel_id" => channel.id, "name" => "  "}, socket)

      reloaded = Channels.get_channel(channel.id)
      assert reloaded.name == "general"
    end

    test "flashes an error for an unknown channel id" do
      socket = build_socket(%{})

      {:noreply, result} =
        RailSessionActions.handle_rename_channel(%{"channel_id" => 999_999_999, "name" => "x"}, socket)

      assert result.assigns.flash["error"] == "Channel not found"
    end
  end
end

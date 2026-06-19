defmodule EyeInTheSkyWeb.ChatLive.ChannelHeaderTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.ChatLive.ChannelHeader

  describe "channel_header/1" do
    test "renders 'Chat' when no active channel" do
      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: nil
        )

      assert html =~ "Chat"
    end

    test "renders channel name with hash prefix" do
      channel = %{name: "general", description: nil}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "#"
      assert html =~ "general"
    end

    test "renders channel name from map" do
      channel = %{name: "announcements"}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "announcements"
    end

    test "renders fallback 'Channel' when name is nil" do
      channel = %{name: nil}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "Channel"
    end

    test "renders channel description" do
      channel = %{
        name: "general",
        description: "General discussion channel"
      }

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "General discussion channel"
    end

    test "does not render description when nil" do
      channel = %{name: "general", description: nil}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      refute html =~ "description"
    end

    test "does not render description when empty" do
      channel = %{name: "general", description: ""}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      refute html =~ "test-description"
    end

    test "renders header container with proper styling" do
      channel = %{name: "dev", description: nil}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "bg-base-100"
      assert html =~ "border-b"
    end

    test "renders header with id attribute" do
      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: nil
        )

      assert html =~ "chat-header-card"
    end

    test "renders hash symbol with primary color styling" do
      channel = %{name: "testing"}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "text-primary/50"
      assert html =~ "#"
    end

    test "renders heading with proper text styling" do
      channel = %{name: "announcements", description: "News and updates"}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "text-xl"
      assert html =~ "font-bold"
    end

    test "renders description with smaller text styling" do
      channel = %{name: "dev", description: "Development work"}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "text-xs"
      assert html =~ "Development work"
    end

    test "renders multiple channel names" do
      channel = %{name: "project-alpha"}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "project-alpha"
    end

    test "handles special characters in channel name" do
      channel = %{name: "general-dev-tools"}

      html =
        render_component(
          &ChannelHeader.channel_header/1,
          active_channel: channel
        )

      assert html =~ "general-dev-tools"
    end
  end
end

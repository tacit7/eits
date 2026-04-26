defmodule EyeInTheSkyWeb.ChatLiveE2ETest do
  @moduledoc """
  Integration tests for ChatLive.

  Tests the web layer: page rendering, channel message events,
  and session list view.
  """

  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Channels, Messages, Projects, Sessions}

  @web_chat_agent_uuid "00000000-0000-0000-0000-000000000001"
  @web_execution_agent_uuid "00000000-0000-0000-0000-000000000002"

  setup %{conn: conn} do
    # Create test project
    {:ok, project} =
      Projects.create_project(%{
        name: "E2E Test Project",
        slug: "e2e-test-project-#{System.unique_integer([:positive])}",
        active: true
      })

    # Create web UI chat agent and execution agent
    {:ok, web_chat_agent} =
      Agents.create_agent(%{
        uuid: @web_chat_agent_uuid,
        description: "Web UI User",
        source: "web",
        project_id: project.id
      })

    {:ok, web_execution_agent} =
      Sessions.create_session(%{
        uuid: @web_execution_agent_uuid,
        agent_id: web_chat_agent.id,
        name: "Web UI",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Create a channel for communication
    {:ok, channel} =
      Channels.create_channel(%{
        name: "E2E Test Channel",
        project_id: project.id,
        session_id: web_execution_agent.id
      })

    %{
      conn: conn,
      project: project,
      web_chat_agent: web_chat_agent,
      web_execution_agent: web_execution_agent,
      channel: channel
    }
  end

  describe "chat page" do
    test "renders channel chat page", %{conn: conn, channel: channel} do
      {:ok, _view, html} = live(conn, ~p"/chat?channel_id=#{channel.id}")
      assert html =~ "Chat"
    end

    test "send_channel_message event persists message", %{
      conn: conn,
      channel: channel,
      web_execution_agent: _web_execution_agent
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "channel:#{channel.id}:messages")

      view
      |> render_hook("send_channel_message", %{
        "channel_id" => to_string(channel.id),
        "body" => "Hello from E2E test"
      })

      # Verify message was saved to the database
      messages = Messages.list_messages_for_channel(channel.id)
      assert Enum.any?(messages, fn m -> m.body == "Hello from E2E test" end)
    end

    test "send_channel_message with empty body is ignored", %{
      conn: conn,
      channel: channel
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      before_count = length(Messages.list_messages_for_channel(channel.id))

      view
      |> render_hook("send_channel_message", %{
        "channel_id" => to_string(channel.id),
        "body" => ""
      })

      after_count = length(Messages.list_messages_for_channel(channel.id))
      assert after_count == before_count
    end

    test "handles missing channel_id gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/chat")
      assert view.pid |> Process.alive?()
    end
  end

  describe "session list view" do
    test "lists all active sessions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sessions")

      # Should have a button to start a new agent/session
      assert has_element?(view, "button", "New Agent")
    end
  end
end

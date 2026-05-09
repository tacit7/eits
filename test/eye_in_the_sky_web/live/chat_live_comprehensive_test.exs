defmodule EyeInTheSkyWeb.ChatLiveComprehensiveTest do
  @moduledoc """
  Comprehensive test suite for ChatLive LiveView.

  Focuses on the core behaviors that are highest-risk and currently untested:
  - mount with session creation and upload configuration
  - channel switching with proper PubSub subscription/unsubscription
  - send_channel_message persistence and broadcast
  - load_older_messages pagination
  - toggle UI elements (members, agent drawer)
  - PubSub message delivery (new_message, agent_working/stopped)
  """

  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, ChannelMessages, Channels, Messages, Projects, Sessions}

  # Phoenix.LiveViewTest.View does not expose socket assigns directly in LV 1.x.
  # Read them from the process state instead.
  defp get_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  setup %{conn: conn} do
    # Create test project
    {:ok, project} =
      Projects.create_project(%{
        name: "Chat Comprehensive Test",
        slug: "chat-comp-#{System.unique_integer([:positive])}",
        active: true
      })

    # Create web UI session
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Web Agent",
        source: "web",
        project_id: project.id
      })

    {:ok, web_session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Web Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Create primary channel
    {:ok, channel} =
      Channels.create_channel(%{
        name: "Primary",
        project_id: project.id,
        session_id: web_session.id
      })

    # Create secondary channel for switching tests
    {:ok, channel2} =
      Channels.create_channel(%{
        name: "Secondary",
        project_id: project.id,
        session_id: web_session.id
      })

    # Create another agent for add/remove tests
    {:ok, agent2} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Other Agent",
        source: "api",
        project_id: project.id
      })

    {:ok, session2} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent2.id,
        name: "Other Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{
      conn: conn,
      project: project,
      channel: channel,
      channel2: channel2,
      web_session: web_session,
      session2: session2
    }
  end

  describe "mount - socket initialization" do
    test "initializes assigns and creates session on connected mount", %{
      conn: conn,
      channel: channel
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      assigns = get_assigns(view)

      # Verify session was created for connected socket
      refute is_nil(assigns.session_id)

      # Verify uploads configured
      assert assigns.uploads[:agent_images] != nil
      upload = assigns.uploads.agent_images
      assert upload.max_entries == 5
      assert upload.max_file_size == 20_000_000
      # accept is a comma-separated string, not a list
      assert String.contains?(upload.accept, ".jpg")
    end

    test "initializes with correct default assigns", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      assigns = get_assigns(view)

      assert assigns.working_agents == %{}
      assert assigns.sidebar_tab == :chat
      assert assigns.show_members == false
      assert assigns.show_agent_drawer == false
    end
  end

  describe "handle_params - channel management" do
    test "subscribes to channel messages on initial load", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      topic = "channel:#{channel.id}:messages"

      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid in subscribers
    end

    test "channel switching unsubscribes and re-subscribes correctly", %{
      conn: conn,
      channel: channel,
      channel2: channel2
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      topic1 = "channel:#{channel.id}:messages"
      topic2 = "channel:#{channel2.id}:messages"

      assert view.pid in (Registry.lookup(EyeInTheSky.PubSub, topic1)
                          |> Enum.map(fn {p, _} -> p end))

      render_patch(view, ~p"/chat?channel_id=#{channel2.id}")

      assert view.pid not in (Registry.lookup(EyeInTheSky.PubSub, topic1)
                              |> Enum.map(fn {p, _} -> p end))

      assert view.pid in (Registry.lookup(EyeInTheSky.PubSub, topic2)
                          |> Enum.map(fn {p, _} -> p end))
    end

    test "repeated patch to same channel doesn't create duplicate subscription", %{
      conn: conn,
      channel: channel
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      topic = "channel:#{channel.id}:messages"

      sub_count_before =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.count(fn {p, _} -> p == view.pid end)

      render_patch(view, ~p"/chat?channel_id=#{channel.id}")

      sub_count_after =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.count(fn {p, _} -> p == view.pid end)

      assert sub_count_before == sub_count_after
    end
  end

  describe "send_channel_message event" do
    test "persists message to database", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      render_hook(view, "send_channel_message", %{
        "channel_id" => to_string(channel.id),
        "body" => "Test message"
      })

      messages = Messages.list_messages_for_channel(channel.id)
      assert Enum.any?(messages, fn m -> m.body == "Test message" end)
    end

    test "ignores empty body", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      count_before = length(Messages.list_messages_for_channel(channel.id))

      render_hook(view, "send_channel_message", %{
        "channel_id" => to_string(channel.id),
        "body" => ""
      })

      count_after = length(Messages.list_messages_for_channel(channel.id))
      assert count_before == count_after
    end
  end

  describe "load_older_messages event" do
    test "prepends older messages to current list", %{
      conn: conn,
      channel: channel,
      web_session: web_session
    } do
      # Create some old messages
      for i <- 1..5 do
        {:ok, _} =
          ChannelMessages.send_channel_message(%{
            channel_id: channel.id,
            session_id: web_session.id,
            sender_role: "agent",
            recipient_role: "user",
            provider: "claude",
            body: "Old #{i}"
          })
      end

      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      initial_count = length(get_assigns(view).messages)

      # Create a reference message
      {:ok, ref_msg} =
        ChannelMessages.send_channel_message(%{
          channel_id: channel.id,
          session_id: web_session.id,
          sender_role: "agent",
          recipient_role: "user",
          provider: "claude",
          body: "Reference"
        })

      # Load older
      render_hook(view, "load_older_messages", %{
        "before_id" => to_string(ref_msg.id)
      })

      # Should have more messages now
      assert length(get_assigns(view).messages) > initial_count
    end

    test "sets has_more_messages flag correctly", %{
      conn: conn,
      channel: channel,
      web_session: web_session
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      {:ok, msg} =
        ChannelMessages.send_channel_message(%{
          channel_id: channel.id,
          session_id: web_session.id,
          sender_role: "agent",
          recipient_role: "user",
          provider: "claude",
          body: "Test"
        })

      render_hook(view, "load_older_messages", %{
        "before_id" => to_string(msg.id)
      })

      # With few messages, has_more should be false
      assert get_assigns(view).has_more_messages == false
    end
  end

  describe "UI toggle events" do
    test "toggle_members toggles boolean", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      assert get_assigns(view).show_members == false

      render_hook(view, "toggle_members", %{})
      assert get_assigns(view).show_members == true

      render_hook(view, "toggle_members", %{})
      assert get_assigns(view).show_members == false
    end

    test "toggle_agent_drawer toggles boolean", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      assert get_assigns(view).show_agent_drawer == false

      render_hook(view, "toggle_agent_drawer", %{})
      assert get_assigns(view).show_agent_drawer == true

      render_hook(view, "toggle_agent_drawer", %{})
      assert get_assigns(view).show_agent_drawer == false
    end
  end

  describe "agent_working/stopped handling" do
    test "agent_working adds session to working_agents map", %{
      conn: conn,
      channel: channel,
      session2: session2
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      # Events.agent_working/1 broadcasts the Session struct; msg.id is the session PK.
      send(view.pid, {:agent_working, session2})
      render(view)

      working = get_assigns(view).working_agents
      assert Map.has_key?(working, session2.id)
      assert working[session2.id] == true
    end

    test "agent_stopped removes session from working_agents map", %{
      conn: conn,
      channel: channel,
      session2: session2
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      # Add to working
      send(view.pid, {:agent_working, session2})
      render(view)
      assert Map.has_key?(get_assigns(view).working_agents, session2.id)

      # Remove from working
      send(view.pid, {:agent_stopped, session2})
      render(view)
      assert not Map.has_key?(get_assigns(view).working_agents, session2.id)
    end
  end

  describe "new_message PubSub handling" do
    test "appends new message to list without full reload", %{
      conn: conn,
      channel: channel,
      web_session: web_session
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      initial_count = length(get_assigns(view).messages)

      # Create message outside the view
      {:ok, new_msg} =
        ChannelMessages.send_channel_message(%{
          channel_id: channel.id,
          session_id: web_session.id,
          sender_role: "agent",
          recipient_role: "user",
          provider: "claude",
          body: "New from broadcast"
        })

      # Broadcast it
      EyeInTheSky.Events.channel_message(channel.id, new_msg)
      render(view)

      # Should have appended (list grows by 1)
      assert length(get_assigns(view).messages) == initial_count + 1

      # Verify new message is in list
      assert Enum.any?(get_assigns(view).messages, fn m ->
               m.body == "New from broadcast"
             end)
    end
  end

  describe "change_channel event" do
    test "routes to new channel view", %{conn: conn, channel: channel, channel2: channel2} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      render_hook(view, "change_channel", %{"channel_id" => to_string(channel2.id)})

      # handle_params receives channel_id as a string from URL params
      assert get_assigns(view).active_channel_id == to_string(channel2.id)
    end
  end

  describe "thread operations" do
    test "open_thread sets active_thread", %{
      conn: conn,
      channel: channel,
      web_session: web_session
    } do
      {:ok, parent} =
        ChannelMessages.send_channel_message(%{
          channel_id: channel.id,
          session_id: web_session.id,
          sender_role: "user",
          recipient_role: "agent",
          provider: "claude",
          body: "Parent"
        })

      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      render_hook(view, "open_thread", %{"message_id" => to_string(parent.id)})

      refute is_nil(get_assigns(view).active_thread)
    end

    test "close_thread clears active_thread", %{
      conn: conn,
      channel: channel,
      web_session: web_session
    } do
      {:ok, parent} =
        ChannelMessages.send_channel_message(%{
          channel_id: channel.id,
          session_id: web_session.id,
          sender_role: "user",
          recipient_role: "agent",
          provider: "claude",
          body: "Parent"
        })

      {:ok, view, _html} =
        live(conn, ~p"/chat?channel_id=#{channel.id}&thread_id=#{parent.id}")

      render_hook(view, "close_thread", %{})

      assert is_nil(get_assigns(view).active_thread)
    end
  end
end

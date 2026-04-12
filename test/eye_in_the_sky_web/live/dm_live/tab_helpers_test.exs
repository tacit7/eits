defmodule EyeInTheSkyWeb.DmLive.TabHelpersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Factory, Messages, Repo}
  alias EyeInTheSkyWeb.DmLive.TabHelpers

  defp build_socket(assigns) do
    base = %{
      __changed__: %{},
      active_tab: "messages",
      message_limit: 20,
      message_search_query: "",
      messages: nil,
      has_more_messages: false,
      total_tokens: {0, 0.0},
      total_cost: {0, 0.0},
      context_used: 0,
      context_window: 0,
      current_task: nil,
      tasks: [],
      commits: [],
      notes: [],
      session_context: nil
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  defp create_message(session_id, body) do
    Messages.create_message(%{
      session_id: session_id,
      sender_role: "user",
      recipient_role: "agent",
      provider: "claude",
      direction: "outbound",
      body: body
    })
  end

  describe "force_reload_messages/2 — cache bypass" do
    test "returns fresh DB messages even when :messages is already assigned" do
      agent = Factory.create_agent() |> Repo.preload(:project)
      session = Factory.create_session(agent)

      {:ok, msg1} = create_message(session.id, "first message")

      socket =
        build_socket(%{
          session_id: session.id,
          session_uuid: session.uuid,
          session: session,
          agent: agent,
          # Pre-load a stale message list (simulates cached state)
          messages: []
        })

      # force_reload_messages must bypass the non-nil :messages cache
      result = TabHelpers.force_reload_messages(socket, session.id)

      message_ids = Enum.map(result.assigns.messages, & &1.id)
      assert msg1.id in message_ids
    end

    test "picks up messages added after cache was populated" do
      agent = Factory.create_agent() |> Repo.preload(:project)
      session = Factory.create_session(agent)

      {:ok, msg1} = create_message(session.id, "original")

      socket =
        build_socket(%{
          session_id: session.id,
          session_uuid: session.uuid,
          session: session,
          agent: agent
        })

      # Initial load — populates cache
      socket = TabHelpers.force_reload_messages(socket, session.id)
      assert length(socket.assigns.messages) == 1

      # New message arrives after cache was set
      {:ok, msg2} = create_message(session.id, "new message")

      # force_reload must return both messages, ignoring the cached single-item list
      result = TabHelpers.force_reload_messages(socket, session.id)
      message_ids = Enum.map(result.assigns.messages, & &1.id)

      assert msg1.id in message_ids
      assert msg2.id in message_ids
    end
  end

  describe "load_tab_data/3 — tab-switch cache preserved" do
    test "returns cached :messages on tab switch without hitting DB for new entries" do
      agent = Factory.create_agent() |> Repo.preload(:project)
      session = Factory.create_session(agent)

      {:ok, _msg1} = create_message(session.id, "cached message")

      stale_cached = [%{id: :fake, body: "stale", metadata: %{}}]

      socket =
        build_socket(%{
          session_id: session.id,
          session_uuid: session.uuid,
          session: session,
          agent: agent,
          messages: stale_cached,
          message_search_query: ""
        })

      # Tab-switch path: load_tab_data with non-nil :messages should return cache
      result = TabHelpers.load_tab_data(socket, "messages", session.id)
      assert result.assigns.messages == stale_cached
    end
  end

  describe "load_more_messages regression" do
    test "force_reload_messages with updated message_limit returns correct number of messages" do
      agent = Factory.create_agent() |> Repo.preload(:project)
      session = Factory.create_session(agent)

      # Create 5 messages
      for i <- 1..5 do
        create_message(session.id, "message #{i}")
      end

      socket =
        build_socket(%{
          session_id: session.id,
          session_uuid: session.uuid,
          session: session,
          agent: agent,
          # Cache has old limit result
          messages: [%{id: :fake, body: "stale"}],
          message_limit: 2
        })

      # Simulate load_more_messages: increase limit then force reload
      socket = %{socket | assigns: Map.put(socket.assigns, :message_limit, 5)}
      result = TabHelpers.force_reload_messages(socket, session.id)

      # Should have up to 5 messages, not the stale single-item cache
      assert length(result.assigns.messages) == 5
    end
  end

  describe "search clear regression" do
    test "force_reload_messages after clearing search returns full list, not filtered cache" do
      agent = Factory.create_agent() |> Repo.preload(:project)
      session = Factory.create_session(agent)

      {:ok, _msg1} = create_message(session.id, "hello world")
      {:ok, _msg2} = create_message(session.id, "something else")
      {:ok, _msg3} = create_message(session.id, "another one")

      socket =
        build_socket(%{
          session_id: session.id,
          session_uuid: session.uuid,
          session: session,
          agent: agent
        })

      # Simulate search: load filtered results into cache
      socket =
        socket
        |> Map.update!(:assigns, &Map.put(&1, :message_search_query, "hello"))
        |> TabHelpers.load_tab_data("messages", session.id)

      assert length(socket.assigns.messages) == 1

      # Clear search: force_reload_messages must restore full list
      socket =
        socket
        |> Map.update!(:assigns, &Map.put(&1, :message_search_query, ""))
        |> then(&TabHelpers.force_reload_messages(&1, session.id))

      assert length(socket.assigns.messages) == 3
    end
  end
end

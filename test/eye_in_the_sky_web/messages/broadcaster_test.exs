defmodule EyeInTheSkyWeb.Messages.BroadcasterTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.Messages.Broadcaster
  alias EyeInTheSkyWeb.Messages.Message
  alias EyeInTheSkyWeb.{Agents, Sessions, Messages}
  import Ecto.Query

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} = Agents.create_agent(%{name: "bc-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: "bc-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  defp insert_message(session_id, body) do
    {:ok, msg} =
      Messages.create_message(%{
        uuid: Ecto.UUID.generate(),
        session_id: session_id,
        sender_role: "agent",
        recipient_role: "user",
        direction: "inbound",
        body: body,
        status: "delivered",
        provider: "claude"
      })

    msg
  end

  defp current_max_id do
    Message
    |> select([m], max(m.id))
    |> Repo.one()
  end

  # -- init --

  test "init tracks current max message id" do
    session = create_session()
    msg = insert_message(session.id, "seed")

    # Temporarily enable for init
    Application.put_env(:eye_in_the_sky_web, Broadcaster, enabled: true)
    {:ok, state} = Broadcaster.init([])
    Application.put_env(:eye_in_the_sky_web, Broadcaster, enabled: false)

    assert state.last_id == msg.id
    assert state.enabled == true
  end

  test "init disabled returns nil last_id" do
    {:ok, state} = Broadcaster.init([])
    assert state.last_id == nil
    assert state.enabled == false
  end

  # -- poll --

  test "poll broadcasts new session messages" do
    session = create_session()
    last_id = current_max_id()

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")

    insert_message(session.id, "hello from external")

    state = %{last_id: last_id, enabled: true}
    {:noreply, new_state} = Broadcaster.handle_info(:poll, state)

    assert_receive {:new_message, %{body: "hello from external"}}, 1_000
    assert new_state.last_id > (last_id || 0)
  end

  test "poll is a no-op when no new messages" do
    session = create_session()
    insert_message(session.id, "old msg")
    last_id = current_max_id()

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")

    state = %{last_id: last_id, enabled: true}
    {:noreply, new_state} = Broadcaster.handle_info(:poll, state)

    refute_receive {:new_message, _}, 200
    assert new_state.last_id == last_id
  end

  test "poll advances last_id" do
    session = create_session()
    last_id = current_max_id()

    msg = insert_message(session.id, "new one")

    state = %{last_id: last_id, enabled: true}
    {:noreply, new_state} = Broadcaster.handle_info(:poll, state)

    assert new_state.last_id == msg.id
  end

  test "poll broadcasts to multiple sessions" do
    s1 = create_session()
    s2 = create_session()
    last_id = current_max_id()

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{s1.id}")
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{s2.id}")

    insert_message(s1.id, "msg for s1")
    insert_message(s2.id, "msg for s2")

    state = %{last_id: last_id, enabled: true}
    {:noreply, _} = Broadcaster.handle_info(:poll, state)

    assert_receive {:new_message, %{body: "msg for s1"}}, 1_000
    assert_receive {:new_message, %{body: "msg for s2"}}, 1_000
  end

  test "poll skips when disabled" do
    state = %{last_id: nil, enabled: false}
    {:noreply, new_state} = Broadcaster.handle_info(:poll, state)
    assert new_state == state
  end

  test "poll from nil last_id does not broadcast existing" do
    session = create_session()
    insert_message(session.id, "pre-existing")

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")

    # nil last_id means first run; get_messages_after(nil) returns []
    state = %{last_id: nil, enabled: true}
    {:noreply, new_state} = Broadcaster.handle_info(:poll, state)

    refute_receive {:new_message, _}, 200
    # But last_id should advance to current max
    assert new_state.last_id != nil
  end
end

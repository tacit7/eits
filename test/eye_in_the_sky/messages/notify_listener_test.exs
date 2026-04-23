defmodule EyeInTheSky.Messages.NotifyListenerTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Agents, Channels, Events, Messages, Sessions}
  alias EyeInTheSky.Messages.{Message, NotifyListener}

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} = Agents.create_agent(%{name: "nl-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  defp create_channel do
    {:ok, channel} =
      Channels.create_channel(%{name: "nl-channel-#{uniq()}", channel_type: "public"})

    channel
  end

  defp start_listener do
    Application.put_env(:eye_in_the_sky, NotifyListener, enabled: true)

    {:ok, pid} = NotifyListener.start_link([])
    Ecto.Adapters.SQL.Sandbox.allow(EyeInTheSky.Repo, self(), pid)

    on_exit(fn ->
      Application.put_env(:eye_in_the_sky, NotifyListener, enabled: false)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    pid
  end

  defp insert_message(attrs) do
    base = %{
      uuid: Ecto.UUID.generate(),
      sender_role: "agent",
      recipient_role: "user",
      direction: "inbound",
      body: "test-body-#{uniq()}",
      status: "delivered",
      provider: "claude"
    }

    {:ok, msg} = Messages.create_message(Map.merge(base, attrs))
    msg
  end

  defp deliver_notify(pid, id) do
    send(pid, {:notification, self(), make_ref(), "messages_inserted", Integer.to_string(id)})
  end

  # -- happy path: session message --

  test "session insert triggers session broadcast" do
    session = create_session()
    Events.subscribe_session(session.id)
    pid = start_listener()

    msg = insert_message(%{session_id: session.id})
    deliver_notify(pid, msg.id)

    assert_receive {:new_message, %Message{id: id}}, 1_000
    assert id == msg.id
  end

  # -- happy path: channel message --

  test "channel-only insert triggers channel broadcast" do
    channel = create_channel()
    Events.subscribe_channel_messages(channel.id)
    pid = start_listener()

    msg = insert_message(%{channel_id: channel.id})
    deliver_notify(pid, msg.id)

    assert_receive {:new_message, %Message{id: id}}, 1_000
    assert id == msg.id
  end

  # -- bad payload: not a number --

  test "bad payload is a no-op and does not crash" do
    pid = start_listener()

    ref = Process.monitor(pid)
    send(pid, {:notification, self(), make_ref(), "messages_inserted", "not_a_number"})

    refute_receive {:DOWN, ^ref, :process, ^pid, _}, 300
    assert Process.alive?(pid)
  end

  # -- deleted row: notify arrives but row is gone --

  test "row deleted between notify and load does not crash" do
    session = create_session()
    pid = start_listener()

    msg = insert_message(%{session_id: session.id})
    Repo.delete!(msg)

    ref = Process.monitor(pid)
    deliver_notify(pid, msg.id)

    refute_receive {:DOWN, ^ref, :process, ^pid, _}, 300
    assert Process.alive?(pid)
  end
end

defmodule EyeInTheSkyWeb.Api.V1.DmWaitTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import EyeInTheSky.Factory

  alias EyeInTheSky.Events
  alias EyeInTheSky.Messages
  alias EyeInTheSkyWeb.Api.V1.MessagingController

  defp insert_dm(recipient, sender) do
    {:ok, message} =
      Messages.create_message(%{
        uuid: Ecto.UUID.generate(),
        session_id: recipient.id,
        to_session_id: recipient.id,
        from_session_id: sender.id,
        sender_role: "agent",
        recipient_role: "agent",
        direction: "inbound",
        body: "private message",
        status: "delivered",
        provider: "claude"
      })

    message
  end

  # Trace only the request process to synchronize with the real receive loop.
  # This avoids sleeps that can broadcast before subscription or the initial query.
  defp start_wait(recipient, caller, timeout) do
    :erlang.trace_pattern({MessagingController, :wait_for_dm, 3}, true, [:local])

    task =
      Task.async(fn ->
        receive do
          :start ->
            build_conn()
            |> put_req_header("x-eits-session", caller)
            |> get(~p"/api/v1/dm/wait", %{"session" => recipient.uuid, "timeout" => timeout})
            |> json_response(200)
        end
      end)

    on_exit(fn ->
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
      :erlang.trace_pattern({MessagingController, :wait_for_dm, 3}, false, [:local])
    end)

    :erlang.trace(task.pid, true, [:call, {:tracer, self()}])
    send(task.pid, :start)
    {task, receive_deadline(task)}
  end

  defp receive_deadline(task) do
    pid = task.pid

    assert_receive {:trace, ^pid, :call,
                    {MessagingController, :wait_for_dm, [_conn, _session, deadline]}},
                   2_000

    deadline
  end

  test "unrelated broadcasts retain the original absolute deadline" do
    recipient = create_session(create_agent())
    {task, deadline} = start_wait(recipient, recipient.uuid, "1")

    # Advance time only after the waiter is synchronized, so resetting the
    # deadline cannot accidentally produce the same millisecond value.
    for sequence <- 1..3 do
      Process.sleep(20)
      Events.session_new_message(recipient.id, %{body: "unrelated #{sequence}"})
      assert receive_deadline(task) == deadline
    end

    assert Task.await(task, 2_000) == %{"items" => [], "count" => 0}
    assert System.monotonic_time(:millisecond) >= deadline
  end

  test "a DM for another recipient on the subscribed topic is ignored" do
    recipient = create_session(create_agent())
    other = create_session(create_agent())
    sender = create_session(create_agent())
    wrong_message = insert_dm(other, sender)
    {task, deadline} = start_wait(recipient, recipient.uuid, "5")

    Events.session_new_dm(recipient.id, wrong_message)
    assert receive_deadline(task) == deadline

    message = insert_dm(recipient, sender)
    Events.session_new_dm(recipient.id, message)
    assert %{"count" => 1, "items" => [%{"id" => id}]} = Task.await(task, 2_000)
    assert id == message.id
  end

  for identity <- [:missing, :other, :invalid], populated? <- [false, true] do
    test "#{identity} caller is denied like GET /dm with populated=#{populated?}" do
      recipient = create_session(create_agent())
      other = create_session(create_agent())
      if unquote(populated?), do: insert_dm(recipient, other)

      conn =
        case unquote(identity) do
          :missing -> build_conn()
          :other -> put_req_header(build_conn(), "x-eits-session", other.uuid)
          :invalid -> put_req_header(build_conn(), "x-eits-session", Ecto.UUID.generate())
        end

      params = %{"session" => recipient.uuid, "timeout" => "0"}
      expected = conn |> get(~p"/api/v1/dm", params) |> json_response(403)
      assert expected["error"] == "You are not the recipient of this message"
      assert conn |> get(~p"/api/v1/dm/wait", params) |> json_response(403) == expected
    end
  end

  for identity <- [:uuid, :id] do
    test "recipient #{identity} can read only its own existing DM like GET /dm" do
      recipient = create_session(create_agent())
      other = create_session(create_agent())
      own_message = insert_dm(recipient, other)
      insert_dm(other, recipient)
      caller = to_string(Map.fetch!(recipient, unquote(identity)))
      conn = put_req_header(build_conn(), "x-eits-session", caller)
      params = %{"session" => caller, "timeout" => "0"}

      listed = conn |> get(~p"/api/v1/dm", params) |> json_response(200)
      waited = conn |> get(~p"/api/v1/dm/wait", params) |> json_response(200)
      assert listed["count"] == 1
      assert waited["count"] == 1
      assert waited["items"] == listed["messages"]
      assert hd(waited["items"])["id"] == own_message.id
    end

    test "recipient #{identity} can receive a DM arriving while waiting" do
      recipient = create_session(create_agent())
      sender = create_session(create_agent())
      caller = to_string(Map.fetch!(recipient, unquote(identity)))
      {task, _deadline} = start_wait(recipient, caller, "5")
      message = insert_dm(recipient, sender)
      Events.session_new_dm(recipient.id, message)

      assert %{"count" => 1, "items" => [%{"id" => id}]} = Task.await(task, 2_000)
      assert id == message.id
    end
  end

  test "both endpoints require API authentication when configured" do
    previous = Application.get_env(:eye_in_the_sky, :api_key)
    Application.put_env(:eye_in_the_sky, :api_key, "dm-wait-test-only")
    on_exit(fn -> Application.put_env(:eye_in_the_sky, :api_key, previous) end)
    recipient = create_session(create_agent())
    params = %{"session" => recipient.uuid, "timeout" => "0"}

    for path <- [~p"/api/v1/dm", ~p"/api/v1/dm/wait"] do
      conn = build_conn() |> put_req_header("x-eits-session", recipient.uuid) |> get(path, params)
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end
end

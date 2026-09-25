defmodule EyeInTheSkyWeb.Api.V1.DmWatchTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import EyeInTheSky.Factory
  alias EyeInTheSky.{Events, Repo}
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSkyWeb.Api.V1.MessagingController

  defp insert_dm(recipient, sender, timestamp) do
    Repo.insert!(%Message{
      uuid: Ecto.UUID.generate(),
      session_id: recipient.id,
      to_session_id: recipient.id,
      from_session_id: sender.id,
      sender_role: "agent",
      recipient_role: "agent",
      direction: "inbound",
      body: "fixture only",
      status: "delivered",
      provider: "claude",
      inserted_at: timestamp,
      updated_at: timestamp
    })
  end

  defp params(recipient, overrides \\ %{}) do
    Map.merge(
      %{
        "session" => recipient.uuid,
        "watch" => "true",
        "since" => "2026-01-01T00:00:00Z",
        "after_id" => "0",
        "timeout" => "0"
      },
      overrides
    )
  end

  defp request(recipient, params) do
    build_conn()
    |> put_req_header("x-eits-session", recipient.uuid)
    |> get(~p"/api/v1/dm/wait", params)
  end

  test "drains oldest first including more than one inbox page at equal timestamps" do
    recipient = create_session(create_agent())
    sender = create_session(create_agent())
    timestamp = ~U[2026-01-01 00:00:00Z]
    messages = for _ <- 1..105, do: insert_dm(recipient, sender, timestamp)
    later = insert_dm(recipient, sender, DateTime.add(timestamp, 1))
    insert_dm(sender, recipient, timestamp)

    {ids, cursor} =
      Enum.reduce(messages ++ [later], {[], params(recipient)}, fn message, {ids, cursor} ->
        response = request(recipient, cursor) |> json_response(200)
        assert response["watch_cursor"] == true
        assert [%{"id" => id, "inserted_at" => timestamp}] = response["items"]
        assert id == message.id
        assert String.ends_with?(timestamp, ".000000Z")
        {ids ++ [id], Map.merge(cursor, %{"since" => timestamp, "after_id" => to_string(id)})}
      end)

    assert ids == Enum.map(messages ++ [later], & &1.id)

    assert request(recipient, cursor) |> json_response(200) == %{
             "items" => [],
             "count" => 0,
             "watch_cursor" => true
           }
  end

  test "same cursor reconnect is deterministic and legacy wait still returns newest" do
    recipient = create_session(create_agent())
    sender = create_session(create_agent())
    last = insert_dm(recipient, sender, ~U[2026-01-01 00:00:02Z])
    first = insert_dm(recipient, sender, ~U[2026-01-01 00:00:01Z])
    first_response = request(recipient, params(recipient)) |> json_response(200)
    assert hd(first_response["items"])["id"] == first.id
    assert request(recipient, params(recipient)) |> json_response(200) == first_response

    next =
      params(recipient, %{
        "since" => "2026-01-01T00:00:01.000000Z",
        "after_id" => to_string(first.id)
      })

    assert hd((request(recipient, next) |> json_response(200))["items"])["id"] == last.id
    legacy = request(recipient, Map.delete(params(recipient), "watch")) |> json_response(200)
    assert hd(legacy["items"])["id"] == last.id
    refute Map.has_key?(legacy, "watch_cursor")
  end

  test "watch rejects invalid cursor instead of ignoring it" do
    recipient = create_session(create_agent())

    for changes <- [
          %{"after_id" => "-1"},
          %{"after_id" => %{"bad" => "value"}},
          %{"after_id" => "1garbage"},
          %{"after_id" => "9223372036854775808"},
          %{"since" => ""},
          %{"since" => "invalid"},
          %{"timeout" => "-1"}
        ] do
      assert request(recipient, params(recipient, changes)) |> json_response(400)
    end
  end

  test "watch preserves recipient authorization" do
    recipient = create_session(create_agent())
    other = create_session(create_agent())

    for caller <- [nil, other.uuid] do
      conn = build_conn()
      conn = if caller, do: put_req_header(conn, "x-eits-session", caller), else: conn
      assert conn |> get(~p"/api/v1/dm/wait", params(recipient)) |> json_response(403)
    end
  end

  test "long poll ignores stale broadcasts and reads committed rows in cursor order" do
    recipient = create_session(create_agent())
    sender = create_session(create_agent())
    stale = insert_dm(recipient, sender, ~U[2025-12-31 23:59:59Z])
    :erlang.trace_pattern({MessagingController, :wait_for_watch, 4}, true, [:local])

    task =
      Task.async(fn ->
        receive do
          :start ->
            request(recipient, params(recipient, %{"timeout" => "3"})) |> json_response(200)
        end
      end)

    on_exit(fn ->
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
      :erlang.trace_pattern({MessagingController, :wait_for_watch, 4}, false, [:local])
    end)

    :erlang.trace(task.pid, true, [:call, {:tracer, self()}])
    send(task.pid, :start)
    pid = task.pid

    assert_receive {:trace, ^pid, :call,
                    {MessagingController, :wait_for_watch, [_, _, _, deadline]}},
                   2_000

    Events.session_new_dm(recipient.id, stale)

    assert_receive {:trace, ^pid, :call,
                    {MessagingController, :wait_for_watch, [_, _, _, ^deadline]}},
                   2_000

    first = insert_dm(recipient, sender, ~U[2026-01-01 00:00:00Z])
    second = insert_dm(recipient, sender, ~U[2026-01-01 00:00:00Z])
    Events.session_new_dm(recipient.id, second)
    result = Task.await(task, 4_000)
    assert hd(result["items"])["id"] == first.id
  end
end

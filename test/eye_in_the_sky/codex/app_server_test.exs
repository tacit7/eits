defmodule EyeInTheSky.Codex.AppServerTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Codex.AppServer

  setup do
    owner_key = {:test, make_ref()}
    fake = start_supervised!({FakeCodexAppServer, self()})
    {:ok, pid} = AppServer.lookup_or_start(owner_key, project_path: "/tmp", transport_pid: fake)
    %{pid: pid, fake: fake}
  end

  test "starts a turn, maps notifications, and emits one terminal result", %{pid: pid} do
    ref = make_ref()
    caller = self()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, caller, "hello", project_path: "/tmp") end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "thread/start", thread_id}
    send_response(pid, thread_id, %{"thread" => %{"id" => "thread-1"}})
    assert_receive {:codex_session_id, ^ref, "thread-1"}

    assert_receive {:fake_request, "turn/start", turn_id}
    send_response(pid, turn_id, %{"turn" => %{"id" => "turn-1"}})
    assert {:ok, ^ref, ^pid} = Task.await(task)

    send_notification(pid, "item/agentMessage/delta", %{
      "threadId" => "thread-1",
      "turnId" => "turn-1",
      "itemId" => "msg-1",
      "delta" => "hello"
    })

    assert_receive {:claude_message, ^ref, %Message{type: :text, content: "hello", delta: true}}

    send_notification(pid, "turn/completed", %{
      "threadId" => "thread-1",
      "turn" => %{"id" => "turn-1", "status" => "completed", "durationMs" => 12},
      "usage" => %{"input_tokens" => 1, "output_tokens" => 2}
    })

    assert_receive {:claude_message, ^ref, %Message{type: :text, content: "hello", delta: false}}
    assert_receive {:claude_message, ^ref, %Message{type: :result, content: "hello"}}
    assert_receive {:claude_complete, ^ref, "thread-1"}

    refute_receive {:claude_error, ^ref, _}, 50
  end

  test "auto-responds to server requests so Codex cannot hang", %{pid: pid} do
    send(
      pid,
      {:codex_app_server_output,
       Jason.encode!(%{
         "jsonrpc" => "2.0",
         "id" => "approval-1",
         "method" => "item/commandExecution/requestApproval",
         "params" => %{"itemId" => "cmd-1"}
       })}
    )

    assert_receive {:fake_response, "approval-1", %{"decision" => "decline"}}
  end

  test "JSON-RPC errors without ids fail the active turn once", %{pid: pid} do
    ref = make_ref()

    task =
      Task.async(fn ->
        AppServer.start_turn(pid, ref, self(), "hello", project_path: "/tmp")
      end)

    assert_receive {:fake_request, "initialize", _init_id}

    send(
      pid,
      {:codex_app_server_output,
       Jason.encode!(%{
         "jsonrpc" => "2.0",
         "error" => %{"code" => -32_000, "message" => "transport failed"}
       })}
    )

    assert {:error, {:codex_app_server_error, "transport failed"}} = Task.await(task)
  end

  test "interrupt sends turn/interrupt for the active turn", %{pid: pid} do
    ref = make_ref()
    caller = self()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, caller, "hello", project_path: "/tmp") end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "thread/start", thread_id}
    send_response(pid, thread_id, %{"thread" => %{"id" => "thread-1"}})

    assert_receive {:fake_request, "turn/start", turn_id}
    send_response(pid, turn_id, %{"turn" => %{"id" => "turn-1"}})
    assert {:ok, ^ref, ^pid} = Task.await(task)

    assert :ok = AppServer.interrupt(pid)
    assert_receive {:fake_request, "turn/interrupt", _interrupt_id}
  end

  test "emits one terminal telemetry event for successful turns", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()
    ref = make_ref()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, self(), "hello", project_path: "/tmp") end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "thread/start", thread_id}
    send_response(pid, thread_id, %{"thread" => %{"id" => "thread-telemetry"}})

    assert_receive {:fake_request, "turn/start", turn_id}
    send_response(pid, turn_id, %{"turn" => %{"id" => "turn-telemetry"}})
    assert {:ok, ^ref, ^pid} = Task.await(task)

    send_notification(pid, "turn/completed", %{
      "threadId" => "thread-telemetry",
      "turn" => %{"id" => "turn-telemetry", "status" => "completed"}
    })

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:turn_accepted], _measurements,
                    %{turn_id: "turn-telemetry"}}

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:turn_completed], _measurements,
                    %{thread_id: "thread-telemetry", turn_id: "turn-telemetry"}}

    refute_receive {:app_server_telemetry, ^telemetry_ref, [:turn_failed], _, _}, 50
    refute_receive {:app_server_telemetry, ^telemetry_ref, [:turn_canceled], _, _}, 50
    refute_receive {:app_server_telemetry, ^telemetry_ref, [:turn_error], _, _}, 50
  end

  test "emits interrupt and canceled telemetry for canceled turns", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()
    ref = make_ref()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, self(), "hello", project_path: "/tmp") end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "thread/start", thread_id}
    send_response(pid, thread_id, %{"thread" => %{"id" => "thread-cancel"}})

    assert_receive {:fake_request, "turn/start", turn_id}
    send_response(pid, turn_id, %{"turn" => %{"id" => "turn-cancel"}})
    assert {:ok, ^ref, ^pid} = Task.await(task)

    assert :ok = AppServer.interrupt(pid)
    assert_receive {:fake_request, "turn/interrupt", _interrupt_id}

    send_notification(pid, "turn/completed", %{
      "threadId" => "thread-cancel",
      "turn" => %{"id" => "turn-cancel", "status" => "canceled"}
    })

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:interrupt], _measurements,
                    %{turn_id: "turn-cancel"}}

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:turn_canceled], _measurements,
                    %{thread_id: "thread-cancel", turn_id: "turn-cancel"}}
  end

  defp send_response(pid, id, result) do
    send(
      pid,
      {:codex_app_server_output,
       Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})}
    )
  end

  defp send_notification(pid, method, params) do
    send(
      pid,
      {:codex_app_server_output,
       Jason.encode!(%{"jsonrpc" => "2.0", "method" => method, "params" => params})}
    )
  end

  defp attach_app_server_telemetry do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, ref}

    events =
      for event <- [
            :interrupt,
            :turn_accepted,
            :turn_completed,
            :turn_failed,
            :turn_canceled,
            :turn_error
          ] do
        [:eits, :codex, :app_server, event]
      end

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _config ->
          suffix = Enum.drop(event, 3)
          send(test_pid, {:app_server_telemetry, ref, suffix, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    ref
  end
end

defmodule FakeCodexAppServer do
  use GenServer

  def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)

  @impl true
  def init(test_pid), do: {:ok, test_pid}

  @impl true
  def handle_info({:codex_app_server_write, _from, json}, test_pid) do
    message = Jason.decode!(json)

    cond do
      Map.has_key?(message, "result") ->
        send(test_pid, {:fake_response, message["id"], message["result"]})

      Map.has_key?(message, "id") ->
        send(test_pid, {:fake_request, message["method"], message["id"]})

      true ->
        send(test_pid, {:fake_notification, message["method"]})
    end

    {:noreply, test_pid}
  end
end

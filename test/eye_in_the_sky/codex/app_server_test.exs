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

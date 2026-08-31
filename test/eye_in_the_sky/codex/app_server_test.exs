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

  test "ignores duplicate terminal notifications after successful completion", %{pid: pid} do
    ref = make_ref()
    caller = self()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, caller, "hello", project_path: "/tmp") end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "thread/start", thread_id}
    send_response(pid, thread_id, %{"thread" => %{"id" => "thread-once"}})
    assert_receive {:codex_session_id, ^ref, "thread-once"}

    assert_receive {:fake_request, "turn/start", turn_id}
    send_response(pid, turn_id, %{"turn" => %{"id" => "turn-once"}})
    assert {:ok, ^ref, ^pid} = Task.await(task)

    send_notification(pid, "item/agentMessage/delta", %{
      "threadId" => "thread-once",
      "turnId" => "turn-once",
      "itemId" => "msg-once",
      "delta" => "done"
    })

    assert_receive {:claude_message, ^ref, %Message{type: :text, content: "done", delta: true}}

    send_notification(pid, "turn/completed", %{
      "threadId" => "thread-once",
      "turn" => %{"id" => "turn-once", "status" => "completed"}
    })

    assert_receive {:claude_message, ^ref, %Message{type: :text, content: "done", delta: false}}
    assert_receive {:claude_message, ^ref, %Message{type: :result, content: "done"}}
    assert_receive {:claude_complete, ^ref, "thread-once"}

    send_notification(pid, "turn/completed", %{
      "threadId" => "thread-once",
      "turn" => %{"id" => "turn-once", "status" => "failed", "error" => %{"message" => "late"}}
    })

    send(pid, {:interrupt_terminal_timeout, ref})

    refute_receive {:claude_message, ^ref, %Message{type: :result}}, 50
    refute_receive {:claude_complete, ^ref, _}, 50
    refute_receive {:claude_error, ^ref, _}, 50
  end

  test "ignores late startup responses after terminal JSON-RPC errors", %{pid: pid} do
    ref = make_ref()
    caller = self()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, caller, "hello", project_path: "/tmp") end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "thread/start", thread_id}
    send_response(pid, thread_id, %{"thread" => %{"id" => "thread-late-startup"}})
    assert_receive {:codex_session_id, ^ref, "thread-late-startup"}

    assert_receive {:fake_request, "turn/start", turn_id}

    send_rpc_error(pid, nil, "transport closed")

    assert {:error, {:codex_app_server_error, "transport closed"}} = Task.await(task)
    assert_receive {:claude_error, ^ref, {:codex_app_server_error, "transport closed"}}

    monitor_ref = Process.monitor(pid)
    send_response(pid, turn_id, %{"turn" => %{"id" => "turn-late-startup"}})

    assert Process.alive?(pid)
    refute_receive {:DOWN, ^monitor_ref, :process, ^pid, _}, 50
    refute_receive {:claude_complete, ^ref, _}, 50
    refute_receive {:claude_message, ^ref, %Message{type: :result}}, 50
  end

  test "auto-responds to server requests so Codex cannot hang", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()

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

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:server_request_replied],
                    _measurements,
                    %{
                      request_id: "approval-1",
                      method: "item/commandExecution/requestApproval",
                      category: :command_approval,
                      item_id: "cmd-1",
                      response_type: :result
                    }}
  end

  test "auto-responds to every supported app-server request shape", %{pid: pid} do
    cases = [
      {"file-1", "item/fileChange/requestApproval", %{"itemId" => "file-change-1"},
       %{"decision" => "decline"}},
      {"permissions-1", "item/permissions/requestApproval", %{"itemId" => "permissions-item"},
       %{"permissions" => %{}, "scope" => "turn"}},
      {"input-1", "tool/requestUserInput",
       %{"questions" => [%{"id" => "choice", "question" => "Continue?"}]},
       %{"answers" => %{"choice" => %{"answers" => []}}}},
      {"input-legacy-1", "item/tool/requestUserInput",
       %{"questions" => [%{"id" => "legacy-choice", "question" => "Continue?"}]},
       %{"answers" => %{"legacy-choice" => %{"answers" => []}}}},
      {"mcp-1", "mcpServer/elicitation/request", %{"serverName" => "example"},
       %{"action" => "decline", "content" => nil, "_meta" => nil}}
    ]

    for {id, method, params, expected} <- cases do
      send(
        pid,
        {:codex_app_server_output,
         Jason.encode!(%{
           "jsonrpc" => "2.0",
           "id" => id,
           "method" => method,
           "params" => Map.merge(%{"threadId" => "thread-1", "turnId" => "turn-1"}, params)
         })}
      )

      assert_receive {:fake_response, ^id, ^expected}
    end
  end

  test "unknown server requests receive JSON-RPC method errors", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()

    send(
      pid,
      {:codex_app_server_output,
       Jason.encode!(%{
         "jsonrpc" => "2.0",
         "id" => "dynamic-tool-1",
         "method" => "item/tool/call",
         "params" => %{"threadId" => "thread-1", "turnId" => "turn-1"}
       })}
    )

    assert_receive {:fake_error, "dynamic-tool-1", %{"code" => -32601, "message" => message}}
    assert message =~ "item/tool/call"

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:server_request_replied],
                    _measurements,
                    %{
                      request_id: "dynamic-tool-1",
                      method: "item/tool/call",
                      category: :unknown,
                      response_type: :error
                    }}
  end

  test "emits telemetry when app-server resolves a server request", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()

    send_notification(pid, "serverRequest/resolved", %{
      "threadId" => "thread-1",
      "turnId" => "turn-1",
      "requestId" => "approval-1"
    })

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:server_request_resolved],
                    _measurements,
                    %{request_id: "approval-1", thread_id: "thread-1", turn_id: "turn-1"}}
  end

  test "stop_owner tolerates a missing registry during cleanup" do
    registry_name = EyeInTheSky.Codex.AppServerRegistry
    registry_pid = Process.whereis(registry_name)

    assert is_pid(registry_pid)

    on_exit(fn ->
      if Process.whereis(registry_name) == nil and Process.alive?(registry_pid) do
        Process.register(registry_pid, registry_name)
      end
    end)

    Process.unregister(registry_name)

    assert :ok = AppServer.stop_owner(:missing_registry_owner)
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

  test "lists hooks through the initialized app-server", %{pid: pid} do
    task = Task.async(fn -> AppServer.list_hooks(pid, ["/tmp"]) end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "hooks/list", hooks_id}
    send_response(pid, hooks_id, %{"hooks" => [%{"name" => "SessionStart"}]})

    assert {:ok, %{"hooks" => [%{"name" => "SessionStart"}]}} = Task.await(task)
  end

  test "emits hook notification telemetry without an active turn", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()

    send_notification(pid, "hook/started", %{
      "hookEventName" => "SessionStart",
      "hookName" => "startup"
    })

    send_notification(pid, "hook/completed", %{
      "hookEventName" => "SessionStart",
      "hookName" => "startup",
      "exitCode" => 0
    })

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:hook_started], _measurements,
                    %{hook_event_name: "SessionStart", hook_name: "startup"}}

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:hook_completed], _measurements,
                    %{hook_event_name: "SessionStart", hook_name: "startup", exit_code: 0}}
  end

  test "extracts hook telemetry from nested app-server run payloads", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()

    send_notification(pid, "hook/completed", %{
      "threadId" => "thread-hooks",
      "run" => %{
        "eventName" => "userPromptSubmit",
        "hookName" => "prompt",
        "exitCode" => 0,
        "trustStatus" => "trusted"
      }
    })

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:hook_completed], _measurements,
                    %{
                      hook_event_name: "userPromptSubmit",
                      hook_name: "prompt",
                      exit_code: 0,
                      trust_status: "trusted"
                    }}
  end

  test "emits one terminal telemetry event for successful turns", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()
    ref = make_ref()
    caller = self()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, caller, "hello", project_path: "/tmp") end)

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

  test "treats documented interrupted turn status as canceled", %{pid: pid} do
    telemetry_ref = attach_app_server_telemetry()
    ref = make_ref()
    caller = self()

    task =
      Task.async(fn -> AppServer.start_turn(pid, ref, caller, "hello", project_path: "/tmp") end)

    assert_receive {:fake_request, "initialize", init_id}
    send_response(pid, init_id, %{})
    assert_receive {:fake_notification, "initialized"}

    assert_receive {:fake_request, "thread/start", thread_id}
    send_response(pid, thread_id, %{"thread" => %{"id" => "thread-interrupted"}})

    assert_receive {:fake_request, "turn/start", turn_id}
    send_response(pid, turn_id, %{"turn" => %{"id" => "turn-interrupted"}})
    assert {:ok, ^ref, ^pid} = Task.await(task)

    send_notification(pid, "turn/completed", %{
      "threadId" => "thread-interrupted",
      "turn" => %{"id" => "turn-interrupted", "status" => "interrupted"}
    })

    assert_receive {:claude_error, ^ref, :canceled}

    assert_receive {:app_server_telemetry, ^telemetry_ref, [:turn_canceled], _measurements,
                    %{thread_id: "thread-interrupted", turn_id: "turn-interrupted"}}
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

  defp send_rpc_error(pid, id, message) do
    error = %{"message" => message}

    payload =
      if is_nil(id) do
        %{"jsonrpc" => "2.0", "error" => error}
      else
        %{"jsonrpc" => "2.0", "id" => id, "error" => error}
      end

    send(pid, {:codex_app_server_output, Jason.encode!(payload)})
  end

  defp attach_app_server_telemetry do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, ref}

    events =
      for event <- [
            :interrupt,
            :hook_started,
            :hook_completed,
            :hooks_list,
            :server_request_replied,
            :server_request_resolved,
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

      Map.has_key?(message, "error") ->
        send(test_pid, {:fake_error, message["id"], message["error"]})

      Map.has_key?(message, "id") ->
        send(test_pid, {:fake_request, message["method"], message["id"]})

      true ->
        send(test_pid, {:fake_notification, message["method"]})
    end

    {:noreply, test_pid}
  end
end

defmodule EyeInTheSky.Pi.SDKTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Claude.SDK.Registry
  alias EyeInTheSky.Pi.SDK
  alias EyeInTheSky.SDK.MessageHandler

  # --- StubCLI --------------------------------------------------------------
  # Records send_ndjson calls for assertions.

  defmodule StubCLI do
    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def sends, do: Agent.get(__MODULE__, & &1) |> Enum.reverse()

    def send_ndjson(_port_or_pid, map) do
      Agent.update(__MODULE__, fn acc -> [map | acc] end)
      :ok
    end

    def cancel(_port), do: :ok

    def spawn_harness(_opts), do: {:error, :stubbed_out}
  end

  # --- helpers --------------------------------------------------------------

  setup do
    Application.put_env(:eye_in_the_sky, :pi_cli_module, StubCLI)
    {:ok, _} = StubCLI.start_link()

    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :pi_cli_module)
    end)

    # Fake "port" — a pid that ignores messages.
    port =
      spawn(fn ->
        receive do
          :never -> :ok
        end
      end)

    sdk_ref = make_ref()
    Registry.register(sdk_ref, port)

    on_exit(fn ->
      Registry.unregister(sdk_ref)
      if Process.alive?(port), do: Process.exit(port, :kill)
    end)

    %{sdk_ref: sdk_ref, port: port}
  end

  defp start_handler(ctx, opts \\ []) do
    test_pid = self()
    sdk_ref = ctx.sdk_ref
    port = ctx.port

    state_opts =
      Keyword.merge(
        [
          session_id: opts[:session_id] || "sess-uuid-1",
          project_path: opts[:project_path] || File.cwd!(),
          model: opts[:model] || "openrouter/qwen/qwen3-coder",
          allowed_tools: ["*"],
          custom_instructions: nil,
          prompt: opts[:prompt] || "hello"
        ],
        opts
      )

    handler =
      spawn_link(fn ->
        state =
          SDK.initial_state(sdk_ref, test_pid, state_opts)
          |> Map.put(:port, port)
          # Simulate the handler bootstrap: send initialize.
          |> then(fn s ->
            id = "pi-#{s.next_id}"
            StubCLI.send_ndjson(port, %{id: id, type: "initialize", protocolVersion: 1})
            %{s | next_id: s.next_id + 1, pending: Map.put(s.pending, id, "initialize")}
          end)

        MessageHandler.run_loop(SDK, state, SDK.loop_opts())
      end)

    # Give handler bootstrap a moment to send initialize.
    Process.sleep(20)
    %{handler: handler, sdk_ref: sdk_ref}
  end

  defp feed(handler, line, sdk_ref \\ nil) do
    ref = sdk_ref || make_ref()
    send(handler, {:claude_output, ref, line})
  end

  defp feed_exit(handler, status, sdk_ref \\ nil) do
    ref = sdk_ref || make_ref()
    send(handler, {:claude_exit, ref, status})
  end

  defp last_send_of(type) do
    StubCLI.sends()
    |> Enum.filter(fn m -> m[:type] == type end)
    |> List.last()
  end

  defp encode(map), do: Jason.encode!(map)

  # --- tests ----------------------------------------------------------------

  test "preamble ordering: initialize -> start_session (after init ok) -> prompt (after ack+ready)",
       ctx do
    %{handler: h} = start_handler(ctx)

    # Initialize was already sent during start_handler.
    assert last_send_of("initialize")

    # Respond OK to initialize.
    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 1}}))
    Process.sleep(30)

    assert last_send_of("start_session"),
           "start_session should be sent after init OK"

    # Prompt should NOT yet be sent — need ready + start_session ack.
    refute last_send_of("prompt")

    # ack start_session.
    feed(h, encode(%{"type" => "response", "id" => "pi-2", "success" => true, "data" => %{}}))
    Process.sleep(30)
    refute last_send_of("prompt"), "prompt should wait until ready arrives"

    # ready arrives (echoing our session id, as the harness contract requires).
    feed(h, encode(%{"type" => "ready", "sessionId" => "sess-uuid-1"}))
    Process.sleep(30)
    assert last_send_of("prompt")
  end

  test "ready before start_session response still gates prompt on both", ctx do
    %{handler: h} = start_handler(ctx)

    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 1}}))
    Process.sleep(30)

    # ready arrives first
    feed(h, encode(%{"type" => "ready", "sessionId" => "sess-uuid-1"}))
    Process.sleep(30)
    refute last_send_of("prompt")

    # then start_session ack
    feed(h, encode(%{"type" => "response", "id" => "pi-2", "success" => true, "data" => %{}}))
    Process.sleep(30)
    assert last_send_of("prompt")
  end

  test "protocol version mismatch halts with claude_error", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 2}}))

    assert_receive {:claude_error, ^ref, {:pi_protocol_version_mismatch, 2}}, 500
  end

  test "failed initialize envelope halts with pi_preamble_failed", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => false,
                     "error" => "nope"}))

    assert_receive {:claude_error, ^ref, {:pi_preamble_failed, "initialize", "nope"}}, 500
  end

  test "exit 0 before turn_end -> claude_error :exit_before_turn_end", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed_exit(h, 0)
    assert_receive {:claude_error, ^ref, :exit_before_turn_end}, 500
  end

  test "exit nonzero before turn_end -> claude_error", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed_exit(h, 137)
    assert_receive {:claude_error, ^ref, {:exit_code, 137}}, 500
  end

  test "turn_end then exit 0 -> claude_complete with eits session id", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx, session_id: "sess-happy")

    # Drive through preamble.
    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 1}}))
    feed(h, encode(%{"type" => "response", "id" => "pi-2", "success" => true, "data" => %{}}))
    feed(h, encode(%{"type" => "ready", "sessionId" => "sess-happy"}))
    Process.sleep(30)

    feed(h, encode(%{"type" => "turn_end", "aggregate" => %{"inputTokens" => 10, "outputTokens" => 20},
                     "totalCostUsd" => 0.01, "durationMs" => 123}))

    assert_receive {:claude_message, ^ref, %Message{type: :result}}, 500
    assert_receive {:claude_complete, ^ref, "sess-happy"}, 500

    feed_exit(h, 0)
  end

  test "turn_error then turn_end -> claude_error {:pi_turn_error, msg} (sticky)", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 1}}))
    feed(h, encode(%{"type" => "response", "id" => "pi-2", "success" => true, "data" => %{}}))
    feed(h, encode(%{"type" => "ready", "sessionId" => "sess-uuid-1"}))
    Process.sleep(30)

    feed(h, encode(%{"type" => "turn_error", "error" => "boom"}))
    feed(h, encode(%{"type" => "turn_end", "aggregate" => %{}}))

    assert_receive {:claude_error, ^ref, {:pi_turn_error, "boom"}}, 500
    refute_receive {:claude_complete, ^ref, _}, 100
  end

  test "turn_error then exit (no turn_end) -> claude_error", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed(h, encode(%{"type" => "turn_error", "error" => "boom"}))
    Process.sleep(30)
    feed_exit(h, 0)

    assert_receive {:claude_error, ^ref, {:pi_turn_error, "boom"}}, 500
  end

  test "assistant_delta lines emit {:claude_message, ref, %Message{delta: true}}", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed(h, encode(%{"type" => "assistant_delta", "delta" => "hello"}))

    assert_receive {:claude_message, ^ref, %Message{type: :text, delta: true, content: "hello"}}, 500
  end

  test "unexpected tool_request is auto-denied and stream continues", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed(h, encode(%{"type" => "tool_request", "requestId" => "req-1", "toolName" => "bash"}))

    assert_receive {:claude_message, ^ref, %Message{type: :text}}, 500
    Process.sleep(30)

    deny = last_send_of("deny_tool")
    assert deny
    assert deny[:requestId] == "req-1"
  end

  test "duplicate terminal: turn_end then error event -> exactly one terminal message", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx, session_id: "dup-sess")

    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 1}}))
    feed(h, encode(%{"type" => "response", "id" => "pi-2", "success" => true, "data" => %{}}))
    feed(h, encode(%{"type" => "ready", "sessionId" => "dup-sess"}))
    Process.sleep(30)

    feed(h, encode(%{"type" => "turn_end", "aggregate" => %{}}))
    assert_receive {:claude_complete, ^ref, "dup-sess"}, 500

    # A subsequent error line should not produce another terminal message.
    feed(h, encode(%{"type" => "error", "error" => "late"}))
    refute_receive {:claude_error, ^ref, _}, 100
    refute_receive {:claude_complete, ^ref, _}, 100
  end

  test "unknown response id -> logged, loop continues", ctx do
    %{handler: h} = start_handler(ctx)

    feed(h, encode(%{"type" => "response", "id" => "pi-999", "success" => true, "data" => %{}}))
    Process.sleep(30)

    assert Process.alive?(h)
  end

  test "malformed line mid-stream -> skipped, loop continues", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)

    feed(h, "not json at all")
    Process.sleep(30)
    assert Process.alive?(h)

    feed(h, encode(%{"type" => "assistant_delta", "delta" => "after garbage"}))
    assert_receive {:claude_message, ^ref, %Message{content: "after garbage"}}, 500
  end

  # --- Codex review fixes (2026-07-06) ---------------------------------------

  defp drive_preamble(h, session_id) do
    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 1}}))
    feed(h, encode(%{"type" => "response", "id" => "pi-2", "success" => true, "data" => %{}}))
    feed(h, encode(%{"type" => "ready", "sessionId" => session_id}))
    Process.sleep(30)
  end

  test "failed prompt envelope arriving after streaming noise halts the turn", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)
    drive_preamble(h, "sess-uuid-1")

    feed(h, encode(%{"type" => "assistant_delta", "delta" => "some noise"}))
    assert_receive {:claude_message, ^ref, %Message{content: "some noise"}}, 500

    feed(h, encode(%{"type" => "response", "id" => "pi-3", "success" => false,
                     "error" => "model rejected prompt"}))

    assert_receive {:claude_error, ^ref, {:pi_preamble_failed, "prompt", "model rejected prompt"}}, 500
    refute_receive {:claude_complete, ^ref, _}, 100
  end

  test "failed mid-turn envelope (deny_tool/dispose) does not kill the turn", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)
    drive_preamble(h, "sess-uuid-1")

    # Trigger an auto-deny so a deny_tool request is pending (id pi-4).
    feed(h, encode(%{"type" => "tool_request", "requestId" => "r1",
                     "toolCallId" => "t1", "kind" => "commandExecution", "input" => %{}}))
    Process.sleep(30)
    assert last_send_of("deny_tool")

    # Its failure response must be non-fatal.
    feed(h, encode(%{"type" => "response", "id" => "pi-4", "success" => false,
                     "error" => "already resolved"}))

    feed(h, encode(%{"type" => "turn_end", "aggregate" => %{}}))
    assert_receive {:claude_complete, ^ref, "sess-uuid-1"}, 500
  end

  test "ready echoing a different sessionId halts with pi_session_mismatch", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx, session_id: "sess-mine")

    feed(h, encode(%{"type" => "response", "id" => "pi-1", "success" => true,
                     "data" => %{"protocolVersion" => 1}}))
    feed(h, encode(%{"type" => "response", "id" => "pi-2", "success" => true, "data" => %{}}))
    feed(h, encode(%{"type" => "ready", "sessionId" => "sess-someone-elses"}))

    assert_receive {:claude_error, ^ref,
                    {:pi_session_mismatch, expected: "sess-mine", got: "sess-someone-elses"}},
                   500

    refute last_send_of("prompt"), "prompt must not be sent to a mismatched session"
  end

  test "cancel then clean exit -> terminal :canceled (not exit_before_turn_end)", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)
    drive_preamble(h, "sess-uuid-1")

    :ok = SDK.cancel(ref)
    feed_exit(h, 0)

    assert_receive {:claude_error, ^ref, :canceled}, 500
  end

  test "cancel then nonzero exit -> terminal :canceled (not exit_code)", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)
    drive_preamble(h, "sess-uuid-1")

    :ok = SDK.cancel(ref)
    feed_exit(h, 143)

    assert_receive {:claude_error, ^ref, :canceled}, 500
  end

  test "cancel then turn_end -> terminal :canceled, never claude_complete", ctx do
    %{handler: h, sdk_ref: ref} = start_handler(ctx)
    drive_preamble(h, "sess-uuid-1")

    :ok = SDK.cancel(ref)
    feed(h, encode(%{"type" => "turn_end", "aggregate" => %{}}))

    assert_receive {:claude_error, ^ref, :canceled}, 500
    refute_receive {:claude_complete, ^ref, _}, 100
  end
end

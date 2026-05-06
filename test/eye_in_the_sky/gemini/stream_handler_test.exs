defmodule EyeInTheSky.Gemini.StreamHandlerTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Gemini.StreamHandler
  alias GeminiCliSdk.Types

  setup do
    case EyeInTheSky.Gemini.StreamHandler.Registry.start_link(nil) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  describe "start/3" do
    test "sends init event as codex_session_id tuple" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123", model: "gemini-2.0"}
      ]

      opts = %{}

      {:ok, sdk_ref, handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert is_reference(sdk_ref)
      assert is_pid(handler_pid)

      assert_receive {:codex_session_id, ^sdk_ref, "session-123"}, 1000
    end

    test "sends assistant message as claude_message tuple" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.MessageEvent{role: "assistant", content: "Hello there"}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, "session-123"}, 1000

      assert_receive {:claude_message, ^sdk_ref, %Message{type: :text, content: "Hello there"}},
                     1000
    end

    test "ignores user messages" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.MessageEvent{role: "user", content: "user message"},
        %Types.MessageEvent{role: "assistant", content: "response"}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, _}, 1000

      assert_receive {:claude_message, ^sdk_ref, %Message{type: :text, content: "response"}},
                     1000

      refute_receive {:claude_message, ^sdk_ref, %Message{type: :text, content: "user message"}},
                     500
    end

    test "sends tool use events" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.ToolUseEvent{
          tool_name: "bash",
          tool_id: "tool-1",
          parameters: %{"command" => "ls"}
        }
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, _}, 1000

      assert_receive {
                       :claude_message,
                       ^sdk_ref,
                       %Message{
                         type: :tool_use,
                         content: "bash",
                         metadata: %{input: %{"command" => "ls"}}
                       }
                     },
                     1000
    end

    test "sends tool result events" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.ToolResultEvent{tool_id: "tool-1", output: "result output"}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, _}, 1000

      assert_receive {
                       :claude_message,
                       ^sdk_ref,
                       %Message{
                         type: :tool_result,
                         content: "result output",
                         metadata: %{tool_id: "tool-1"}
                       }
                     },
                     1000
    end

    test "sends result ok event and completion" do
      test_pid = self()

      stats = %GeminiCliSdk.Types.Stats{
        total_tokens: 100,
        input_tokens: 50,
        output_tokens: 50,
        duration_ms: 1000,
        tool_calls: 0
      }

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.ResultEvent{status: "ok", stats: stats}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, _}, 1000

      assert_receive {
                       :claude_message,
                       ^sdk_ref,
                       %Message{
                         type: :result,
                         metadata: %{total_tokens: 100, input_tokens: 50, output_tokens: 50}
                       }
                     },
                     1000

      assert_receive {:claude_complete, ^sdk_ref, "session-123"}, 1000
    end

    test "sends result success event and completion" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.ResultEvent{status: "success"}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, _}, 1000
      assert_receive {:claude_complete, ^sdk_ref, "session-123"}, 1000
    end

    test "registry entry is cleaned up when handler task terminates" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "cleanup-sess"},
        %Types.MessageEvent{role: "assistant", content: "hi"},
        %Types.ResultEvent{status: "ok"}
      ]

      {:ok, sdk_ref, handler_pid} =
        StreamHandler.start("prompt", %{}, test_pid, stream_fn: fn -> stream end)

      # Entry exists while task is alive (or just before it exits).
      assert_receive {:claude_complete, ^sdk_ref, "cleanup-sess"}, 1000

      # Wait for the handler task to terminate, which triggers :DOWN in Registry.
      ref = Process.monitor(handler_pid)
      assert_receive {:DOWN, ^ref, :process, ^handler_pid, _}, 1000

      # Sync: :sys.get_state blocks until the Registry GenServer drains its
      # mailbox, guaranteeing the :DOWN message has been processed.
      _ = :sys.get_state(EyeInTheSky.Gemini.StreamHandler.Registry)
      assert EyeInTheSky.Gemini.StreamHandler.Registry.lookup(sdk_ref) == nil
    end

    test "result message carries accumulated assistant text" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-abc"},
        %Types.MessageEvent{role: "assistant", content: "Hello, "},
        %Types.MessageEvent{role: "assistant", content: "world!"},
        %Types.ResultEvent{status: "ok"}
      ]

      {:ok, sdk_ref, _pid} =
        StreamHandler.start("prompt", %{}, test_pid, stream_fn: fn -> stream end)

      assert_receive {:claude_message, ^sdk_ref,
                      %Message{type: :result, content: "Hello, world!"}},
                     1000

      assert_receive {:claude_complete, ^sdk_ref, "session-abc"}, 1000
    end

    test "sends error on result error event" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.ResultEvent{status: "error", error: "Some error occurred"}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, _}, 1000
      assert_receive {:claude_error, ^sdk_ref, {:gemini_error, "Some error occurred"}}, 1000
    end

    test "sends error on error event" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-123"},
        %Types.ErrorEvent{message: "Fatal error"}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, _}, 1000
      assert_receive {:claude_error, ^sdk_ref, {:gemini_error, "Fatal error"}}, 1000
    end
  end

  describe "resume/4" do
    test "resumes a session and processes events" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-456"},
        %Types.MessageEvent{role: "assistant", content: "Resumed response"}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.resume("session-456", "continue", opts, test_pid,
          stream_fn: fn -> stream end
        )

      assert_receive {:codex_session_id, ^sdk_ref, "session-456"}, 1000
      assert_receive {:claude_message, ^sdk_ref, %Message{type: :text}}, 1000
    end
  end

  describe "cancel/1" do
    test "cancels a running session" do
      test_pid = self()

      # Stream that emits InitEvent immediately then blocks forever.
      # This prevents the task from completing before cancel/1 is called,
      # which avoids a race where the registry entry is cleaned up via :DOWN
      # before the test can invoke cancel. The task is killed by cancel/1 while
      # it is sleeping inside the stream, so the registry entry is still present.
      stream =
        Stream.resource(
          fn -> :init end,
          fn
            :init ->
              {[%Types.InitEvent{session_id: "session-789"}], :blocking}

            :blocking ->
              Process.sleep(:infinity)
              {[], :done}
          end,
          fn _ -> :ok end
        )

      opts = %{}

      {:ok, sdk_ref, handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, "session-789"}, 1000

      :ok = StreamHandler.cancel(sdk_ref)

      # Stream was blocked before MessageEvent — it was never delivered.
      refute_receive {:claude_message, ^sdk_ref, _}, 100
      Process.sleep(100)
      refute Process.alive?(handler_pid)
    end

    test "returns error for non-existent reference" do
      sdk_ref = make_ref()
      assert {:error, :not_found} = StreamHandler.cancel(sdk_ref)
    end
  end

  describe "event translation" do
    test "full message flow with tool use and result" do
      test_pid = self()

      stream = [
        %Types.InitEvent{session_id: "session-full"},
        %Types.MessageEvent{role: "assistant", content: "I will run a command"},
        %Types.ToolUseEvent{tool_name: "bash", tool_id: "tool-1", parameters: %{"cmd" => "pwd"}},
        %Types.ToolResultEvent{tool_id: "tool-1", output: "/home/user"},
        %Types.MessageEvent{role: "assistant", content: "Done"},
        %Types.ResultEvent{status: "ok", stats: %GeminiCliSdk.Types.Stats{}}
      ]

      opts = %{}

      {:ok, sdk_ref, _handler_pid} =
        StreamHandler.start("test prompt", opts, test_pid, stream_fn: fn -> stream end)

      assert_receive {:codex_session_id, ^sdk_ref, "session-full"}, 1000

      assert_receive {:claude_message, ^sdk_ref,
                      %Message{type: :text, content: "I will run a command"}},
                     1000

      assert_receive {:claude_message, ^sdk_ref, %Message{type: :tool_use, content: "bash"}},
                     1000

      assert_receive {:claude_message, ^sdk_ref,
                      %Message{type: :tool_result, content: "/home/user"}},
                     1000

      assert_receive {:claude_message, ^sdk_ref, %Message{type: :text, content: "Done"}}, 1000
      assert_receive {:claude_message, ^sdk_ref, %Message{type: :result}}, 1000
      assert_receive {:claude_complete, ^sdk_ref, "session-full"}, 1000
    end
  end
end

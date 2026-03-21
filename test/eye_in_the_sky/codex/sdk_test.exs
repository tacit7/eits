defmodule EyeInTheSky.Codex.SDKTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Codex.SDK
  alias EyeInTheSky.Claude.{Message, SDK.Registry}

  # ---------------------------------------------------------------------------
  # start/2
  # ---------------------------------------------------------------------------

  describe "SDK.start/2" do
    test "requires :to option" do
      assert_raise KeyError, fn ->
        SDK.start("Hello")
      end
    end

    test "returns {:ok, ref, handler_pid} with mock CLI" do
      {:ok, ref, _handler} = SDK.start("say hello", to: self(), project_path: "/tmp")
      assert is_reference(ref)

      # Clean up
      SDK.cancel(ref)
    end

    test "registers ref in SDK.Registry" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)
      assert mock_port != nil

      SDK.cancel(ref)
    end
  end

  # ---------------------------------------------------------------------------
  # resume/3
  # ---------------------------------------------------------------------------

  describe "SDK.resume/3" do
    test "requires :to option" do
      assert_raise KeyError, fn ->
        SDK.resume("thread-123", "Continue")
      end
    end

    test "returns {:ok, ref, handler_pid} with mock CLI" do
      {:ok, ref, _handler} =
        SDK.resume("thread-123", "continue", to: self(), project_path: "/tmp")

      assert is_reference(ref)

      SDK.cancel(ref)
    end
  end

  # ---------------------------------------------------------------------------
  # cancel/1
  # ---------------------------------------------------------------------------

  describe "SDK.cancel/1" do
    test "returns {:error, :not_found} for unknown ref" do
      ref = make_ref()
      assert {:error, :not_found} = SDK.cancel(ref)
    end

    test "returns :ok for running session" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      assert :ok = SDK.cancel(ref)
    end
  end

  # ---------------------------------------------------------------------------
  # Message flow: agent_message -> turn.completed -> result + complete
  # ---------------------------------------------------------------------------

  describe "message flow" do
    test "agent_message text is delivered as :text message" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      # Send thread.started
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "thread.started",
           "thread_id" => "thread-abc"
         })}
      )

      # Send agent_message
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "item.completed",
           "item" => %{"type" => "agent_message", "text" => "Hello from Codex"}
         })}
      )

      assert_receive {:claude_message, ^ref, %Message{type: :text, content: "Hello from Codex"}},
                     5_000
    end

    test "turn.completed sends result with accumulated text then complete" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      # thread.started
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "thread.started",
           "thread_id" => "thread-xyz"
         })}
      )

      # agent_message
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "item.completed",
           "item" => %{"type" => "agent_message", "text" => "The answer is 42"}
         })}
      )

      # Consume the text message
      assert_receive {:claude_message, ^ref, %Message{type: :text}}, 5_000

      # turn.completed
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "turn.completed",
           "thread_id" => "thread-xyz",
           "usage" => %{"input_tokens" => 100, "output_tokens" => 20}
         })}
      )

      # Should receive result message with accumulated text
      assert_receive {:claude_message, ^ref,
                      %Message{type: :result, content: "The answer is 42"}},
                     5_000

      # Should receive completion
      assert_receive {:claude_complete, ^ref, "thread-xyz"}, 5_000
    end

    test "multiple agent_messages accumulate into result" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "thread.started",
           "thread_id" => "thread-multi"
         })}
      )

      # First message
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "item.completed",
           "item" => %{"type" => "agent_message", "text" => "Part one. "}
         })}
      )

      assert_receive {:claude_message, ^ref, %Message{type: :text, content: "Part one. "}}, 5_000

      # Second message
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "item.completed",
           "item" => %{"type" => "agent_message", "text" => "Part two."}
         })}
      )

      assert_receive {:claude_message, ^ref, %Message{type: :text, content: "Part two."}}, 5_000

      # Complete the turn
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "turn.completed",
           "usage" => %{"input_tokens" => 50, "output_tokens" => 30}
         })}
      )

      # Result should contain accumulated text
      assert_receive {:claude_message, ^ref, %Message{type: :result, content: result_text}}, 5_000
      assert result_text == "Part one. Part two."

      assert_receive {:claude_complete, ^ref, _session_id}, 5_000
    end
  end

  # ---------------------------------------------------------------------------
  # Thinking messages
  # ---------------------------------------------------------------------------

  describe "thinking messages" do
    test "reasoning items delivered as thinking messages" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "item.completed",
           "item" => %{"type" => "reasoning", "text" => "Let me think..."}
         })}
      )

      assert_receive {:claude_message, ^ref,
                      %Message{type: :thinking, content: "Let me think..."}},
                     5_000
    end
  end

  # ---------------------------------------------------------------------------
  # Tool use messages
  # ---------------------------------------------------------------------------

  describe "tool use messages" do
    test "command_execution item delivered as tool_use" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "item.completed",
           "item" => %{
             "type" => "command_execution",
             "command" => "ls -la",
             "exit_code" => 0,
             "output" => "total 42\n"
           }
         })}
      )

      assert_receive {:claude_message, ^ref, %Message{type: :tool_use} = msg}, 5_000
      assert msg.content.name == "command_execution"
      assert msg.content.input.command == "ls -la"
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "error event sends claude_error" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "error",
           "message" => "Authentication failed"
         })}
      )

      assert_receive {:claude_error, ^ref, {:codex_error, "Authentication failed"}}, 5_000
    end

    test "non-zero exit sends claude_error" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      send(mock_port, {:exit, 1})

      assert_receive {:claude_error, ^ref, {:exit_code, 1}}, 5_000
    end

    test "clean exit without turn.completed sends complete" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      send(mock_port, {:exit, 0})

      assert_receive {:claude_complete, ^ref, _session_id}, 5_000
    end
  end

  # ---------------------------------------------------------------------------
  # Orphan handler cleanup
  # ---------------------------------------------------------------------------

  describe "orphan handler cleanup" do
    test "handler cleans up registry when caller dies while in handle_messages" do
      caller_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, ref, _handler} = SDK.start("hello", to: caller_pid, project_path: "/tmp")

      mock_port = Registry.lookup(ref)
      assert is_pid(mock_port)

      # Make mock port hang so handler stays in handle_messages waiting
      send(mock_port, :hang)

      Process.sleep(50)

      # Kill the caller - without the fix, handler stays alive with orphan port
      Process.exit(caller_pid, :kill)

      # After fix: handler sees {:DOWN, ...} and calls stop_and_unregister
      Process.sleep(100)
      assert Registry.lookup(ref) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Skip/noise handling
  # ---------------------------------------------------------------------------

  describe "noise handling" do
    test "non-JSON lines are silently skipped" do
      {:ok, ref, _handler} = SDK.start("test", to: self(), project_path: "/tmp")
      mock_port = Registry.lookup(ref)

      # Send stderr/tracing noise
      send(mock_port, {:send_output, "2026-02-16T10:00:00Z TRACE some rust log"})

      # Send a real event after noise
      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "item.completed",
           "item" => %{"type" => "agent_message", "text" => "after noise"}
         })}
      )

      # Should only receive the real message, not the noise
      assert_receive {:claude_message, ^ref, %Message{type: :text, content: "after noise"}}, 5_000

      SDK.cancel(ref)
    end
  end
end

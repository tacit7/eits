defmodule EyeInTheSky.Claude.SDKTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.{Message, SDK}

  describe "SDK.start/2" do
    test "requires :to option" do
      assert_raise KeyError, fn ->
        SDK.start("Hello")
      end
    end

    test "returns {:ok, ref, handler_pid} when successful" do
      {:ok, ref, _handler} =
        SDK.start("Say hello",
          to: self(),
          cli_module: EyeInTheSky.Claude.MockCLI,
          model: "haiku",
          max_turns: 1
        )

      assert is_reference(ref)

      mock_port = SDK.Registry.lookup(ref)
      assert is_pid(mock_port)

      send(mock_port, {:send_output, assistant_line("hello")})

      assert_receive {:claude_message, ^ref, %Message{type: :text, content: "hello"}}, 1_000

      SDK.cancel(ref)
    end

    test "sends parsed messages to caller" do
      {:ok, ref, _handler} =
        SDK.start("Count to 3",
          to: self(),
          cli_module: EyeInTheSky.Claude.MockCLI,
          model: "haiku",
          max_turns: 1
        )

      mock_port = SDK.Registry.lookup(ref)
      assert is_pid(mock_port)

      send(mock_port, {:send_output, assistant_line("one two three")})
      send(mock_port, {:send_output, result_line("session-123", "done")})
      send(mock_port, {:exit, 0})

      {messages, session_id} = collect_messages_until_complete(ref, [])

      # Should receive text messages
      text_messages = Enum.filter(messages, &(&1.type == :text))
      assert text_messages != []

      # Should get completion
      assert session_id == "session-123"
    end
  end

  describe "SDK.resume/3" do
    test "requires :to option" do
      assert_raise KeyError, fn ->
        SDK.resume("session-123", "Continue")
      end
    end
  end

  describe "SDK.cancel/1" do
    test "returns :ok for running session" do
      unless System.get_env("CI") do
        {:ok, ref, _handler} = SDK.start("Write a long essay", to: self(), model: "haiku")

        # Give it a moment to start
        Process.sleep(100)

        assert :ok = SDK.cancel(ref)

        # Should receive error message
        assert_receive {:claude_error, ^ref, _reason}, 5_000
      end
    end

    test "returns {:error, :not_found} for unknown ref" do
      ref = make_ref()
      assert {:error, :not_found} = SDK.cancel(ref)
    end

    test "result is_error closes stream and sends claude_error" do
      {:ok, ref, _handler} =
        SDK.start("hello", to: self(), cli_module: EyeInTheSky.Claude.MockCLI, model: "haiku")

      mock_port = SDK.Registry.lookup(ref)
      assert is_pid(mock_port)

      send(
        mock_port,
        {:send_output,
         Jason.encode!(%{
           "type" => "result",
           "session_id" => "session-123",
           "is_error" => true,
           "result" => "",
           "errors" => ["CLI failed"]
         })}
      )

      send(mock_port, {:exit, 1})

      assert_receive {:claude_error, ^ref, {:claude_result_error, reason}}, 5_000
      assert reason.session_id == "session-123"

      # Stream should be unregistered once terminal event is handled
      Process.sleep(50)
      assert SDK.Registry.lookup(ref) == nil
    end
  end

  describe "handler_start_failed error path" do
    test "returns {:error, {:handler_start_failed, reason}} when TaskSupervisor is at max_children" do
      {:ok, sup} = Task.Supervisor.start_link(max_children: 0)

      result =
        SDK.start("hello",
          to: self(),
          cli_module: EyeInTheSky.Claude.MockCLI,
          task_supervisor: sup,
          model: "haiku"
        )

      assert {:error, {:handler_start_failed, _reason}} = result
    end
  end

  describe "orphan handler cleanup" do
    test "handler cleans up registry when caller dies while in handle_messages" do
      # Spawn a separate caller process so we can kill it independently
      caller_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, ref, _handler} =
        SDK.start("hello",
          to: caller_pid,
          cli_module: EyeInTheSky.Claude.MockCLI,
          model: "haiku"
        )

      mock_port = SDK.Registry.lookup(ref)
      assert is_pid(mock_port)

      # Make mock port hang so handler stays in handle_messages waiting
      send(mock_port, :hang)

      # Give handler time to enter handle_messages
      Process.sleep(50)

      # Kill the caller - without the fix, the handler stays alive and the registry
      # entry is never cleaned up (orphan port)
      Process.exit(caller_pid, :kill)

      # After fix: handler sees {:DOWN, ...} and calls stop_and_unregister
      Process.sleep(100)
      assert SDK.Registry.lookup(ref) == nil
    end
  end

  defp collect_messages_until_complete(ref, acc) do
    receive do
      {:claude_message, ^ref, message} ->
        collect_messages_until_complete(ref, [message | acc])

      {:claude_complete, ^ref, session_id} ->
        {Enum.reverse(acc), session_id}

      {:claude_error, ^ref, _reason} ->
        {Enum.reverse(acc), nil}
    after
      1_000 -> {Enum.reverse(acc), nil}
    end
  end

  defp assistant_line(text) do
    Jason.encode!(%{
      "type" => "assistant",
      "message" => %{"content" => [%{"type" => "text", "text" => text}]}
    })
  end

  defp result_line(session_id, result) do
    Jason.encode!(%{
      "type" => "result",
      "session_id" => session_id,
      "result" => result,
      "is_error" => false
    })
  end
end

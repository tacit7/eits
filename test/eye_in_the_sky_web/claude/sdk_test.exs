defmodule EyeInTheSkyWeb.Claude.SDKTest do
  use ExUnit.Case, async: false

  alias EyeInTheSkyWeb.Claude.{SDK, Message}

  describe "SDK.start/2" do
    test "requires :to option" do
      assert_raise KeyError, fn ->
        SDK.start("Hello")
      end
    end

    test "returns {:ok, ref} when successful" do
      # This would spawn a real Claude process - skip in CI
      unless System.get_env("CI") do
        {:ok, ref} = SDK.start("Say hello", to: self(), model: "haiku", max_turns: 1)
        assert is_reference(ref)

        # Receive at least one message
        assert_receive {:claude_message, ^ref, %Message{}}, 30_000

        # Clean up
        SDK.cancel(ref)
      end
    end

    test "sends parsed messages to caller" do
      unless System.get_env("CI") do
        {:ok, ref} = SDK.start("Count to 3", to: self(), model: "haiku", max_turns: 1)

        messages = collect_messages(ref, [])

        # Should receive text messages
        text_messages = Enum.filter(messages, &(&1.type == :text))
        assert length(text_messages) > 0

        # Should get completion
        assert_receive {:claude_complete, ^ref, session_id}, 30_000
        assert is_binary(session_id)
      end
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
        {:ok, ref} = SDK.start("Write a long essay", to: self(), model: "haiku")

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
      {:ok, ref} =
        SDK.start("hello", to: self(), cli_module: EyeInTheSkyWeb.Claude.MockCLI, model: "haiku")

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

  # Helper to collect messages until completion or timeout
  defp collect_messages(ref, acc) do
    receive do
      {:claude_message, ^ref, message} ->
        collect_messages(ref, [message | acc])

      {:claude_complete, ^ref, _session_id} ->
        Enum.reverse(acc)

      {:claude_error, ^ref, _reason} ->
        Enum.reverse(acc)
    after
      30_000 -> Enum.reverse(acc)
    end
  end
end

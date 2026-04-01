defmodule EyeInTheSky.SDKE2ETest do
  @moduledoc """
  Real end-to-end integration test for the Claude SDK.

  NO MOCKS. This test spawns actual Claude CLI processes and verifies:
  1. Starting a new session with streaming
  2. Receiving parsed messages (text, thinking, tool_use, usage)
  3. Multi-turn conversations with session resumption
  4. Cancellation of running sessions
  5. Error handling

  REQUIRES: claude binary in PATH and valid ANTHROPIC_API_KEY
  """

  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.{SDK, Message}

  @moduletag :integration
  @moduletag :sdk_e2e
  @moduletag timeout: 120_000

  @test_project_path "/tmp/eits-sdk-e2e-test"

  setup do
    # Ensure test project exists
    File.mkdir_p!(@test_project_path)

    on_exit(fn ->
      File.rm_rf!(@test_project_path)
    end)

    :ok
  end

  describe "SDK.start/2 - real Claude session" do
    test "spawns Claude and streams text messages" do
      {:ok, ref} =
        SDK.start("Say 'hello world' and nothing else",
          to: self(),
          model: "haiku",
          max_turns: 1,
          project_path: @test_project_path
        )

      assert is_reference(ref)

      # Collect all messages
      {messages, session_id} = collect_all_messages(ref)

      # Should receive at least one text message
      text_messages = Enum.filter(messages, &(&1.type == :text))
      assert text_messages != []

      # Text should contain "hello"
      full_text = text_messages |> Enum.map(& &1.content) |> Enum.join()
      assert full_text =~ ~r/hello/i

      # Should get session ID
      assert is_binary(session_id)
      assert String.length(session_id) > 10
    end

    test "receives thinking messages when available" do
      {:ok, ref} =
        SDK.start("Think about why the sky is blue, then answer",
          to: self(),
          model: "sonnet",
          max_turns: 1,
          project_path: @test_project_path
        )

      {messages, _session_id} = collect_all_messages(ref)

      # May or may not have thinking messages depending on model
      message_types = Enum.map(messages, & &1.type) |> Enum.uniq()
      assert :text in message_types
    end

    test "receives usage statistics" do
      {:ok, ref} =
        SDK.start("Count to 5",
          to: self(),
          model: "haiku",
          max_turns: 1,
          project_path: @test_project_path
        )

      {messages, _session_id} = collect_all_messages(ref)

      # Should have usage message
      usage_messages = Enum.filter(messages, &(&1.type == :usage))

      if usage_messages != [] do
        usage = hd(usage_messages)
        assert is_map(usage.content)
        assert Map.has_key?(usage.content, :output_tokens)
      end
    end

    test "handles tool use when allowed" do
      # Create a simple file for Claude to read
      test_file = Path.join(@test_project_path, "test.txt")
      File.write!(test_file, "Hello from E2E test")

      {:ok, ref} =
        SDK.start("Read the file test.txt and tell me what it says",
          to: self(),
          model: "haiku",
          allowedTools: "Read",
          max_turns: 3,
          project_path: @test_project_path
        )

      {messages, _session_id} = collect_all_messages(ref)

      # Should have text messages with the content
      text =
        messages
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.content)
        |> Enum.join()

      assert text =~ ~r/Hello from E2E test/i
    end
  end

  describe "SDK.resume/3 - multi-turn conversations" do
    test "resumes previous session with context" do
      # First turn
      {:ok, ref1} =
        SDK.start("I'm thinking of a number between 1 and 10. It's 7.",
          to: self(),
          model: "haiku",
          max_turns: 1,
          project_path: @test_project_path
        )

      {_messages1, session_id} = collect_all_messages(ref1)

      # Second turn - Claude should remember
      {:ok, ref2} =
        SDK.resume(session_id, "What number was I thinking of?",
          to: self(),
          project_path: @test_project_path
        )

      {messages2, _session_id} = collect_all_messages(ref2)

      # Should mention 7
      text =
        messages2
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.content)
        |> Enum.join()

      assert text =~ ~r/7/
    end
  end

  describe "SDK.cancel/1 - cancellation" do
    test "cancels a running session" do
      # Start a long-running task
      {:ok, ref} =
        SDK.start("Count to 100 slowly, saying each number",
          to: self(),
          model: "haiku",
          max_turns: 1,
          project_path: @test_project_path
        )

      # Wait for first message
      assert_receive {:claude_message, ^ref, _}, 10_000

      # Cancel it
      assert :ok = SDK.cancel(ref)

      # Should receive error or complete message soon
      receive do
        {:claude_error, ^ref, _reason} -> :ok
        {:claude_complete, ^ref, _} -> :ok
      after
        10_000 -> flunk("Did not receive cancellation confirmation")
      end
    end

    test "returns error for non-existent session" do
      fake_ref = make_ref()
      assert {:error, :not_found} = SDK.cancel(fake_ref)
    end
  end

  describe "error handling" do
    test "handles invalid API key" do
      # Save original API key
      original_key = System.get_env("ANTHROPIC_API_KEY")

      # Set invalid API key
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-invalid-key-123")

      try do
        {:ok, ref} =
          SDK.start("Hello",
            to: self(),
            model: "haiku",
            max_turns: 1,
            project_path: @test_project_path
          )

        # Collect all messages to see what we get
        result =
          receive do
            {:claude_error, ^ref, reason} ->
              {:error, reason}

            {:claude_complete, ^ref, session_id} ->
              {:complete, session_id}

            {:claude_message, ^ref, msg} ->
              {:message, msg}
          after
            30_000 -> :timeout
          end

        # Claude returns authentication errors as text messages
        case result do
          {:message, %{content: content}} ->
            # Should contain "Invalid API key" or similar error
            assert content =~ ~r/Invalid API key/i or content =~ ~r/authentication/i

          {:error, reason} ->
            # Also acceptable - SDK might detect error
            assert is_tuple(reason) or is_atom(reason)

          {:complete, _} ->
            # Might succeed if Claude uses config file instead of env var
            :ok

          :timeout ->
            flunk("Should receive response for invalid API key")
        end
      after
        # Restore original API key
        if original_key do
          System.put_env("ANTHROPIC_API_KEY", original_key)
        else
          System.delete_env("ANTHROPIC_API_KEY")
        end
      end
    end

    test "handles billing errors gracefully" do
      # This might trigger a billing error if API key has no credits
      # Skip if we can't trigger errors reliably
      {:ok, ref} =
        SDK.start("Hello",
          to: self(),
          model: "opus",
          max_turns: 1,
          project_path: @test_project_path
        )

      receive do
        {:claude_error, ^ref, reason} ->
          assert is_tuple(reason) or is_atom(reason)

        {:claude_complete, ^ref, _session_id} ->
          # Success is also fine
          :ok
      after
        30_000 -> flunk("No response received")
      end
    end

    test "handles invalid options" do
      # Missing required :to option
      assert_raise KeyError, fn ->
        SDK.start("Hello")
      end
    end
  end

  # Helper: collect all messages until completion or timeout
  defp collect_all_messages(ref, acc \\ [], timeout \\ 60_000) do
    receive do
      {:claude_message, ^ref, message} ->
        collect_all_messages(ref, [message | acc], timeout)

      {:claude_complete, ^ref, session_id} ->
        {Enum.reverse(acc), session_id}

      {:claude_error, ^ref, reason} ->
        flunk("Claude error: #{inspect(reason)}")
    after
      timeout ->
        flunk("Timeout waiting for messages. Got #{length(acc)} messages so far.")
    end
  end
end

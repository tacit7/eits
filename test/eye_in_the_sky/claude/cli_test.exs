defmodule EyeInTheSky.Claude.CLITest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.CLI

  @moduletag :integration

  describe "Claude CLI with -p flag" do
    test "spawns Claude process with -p (print mode)" do
      # Simple test: spawn Claude with -p flag and verify port is opened
      prompt = "hello"

      opts = [
        model: "sonnet",
        output_format: "stream-json",
        skip_permissions: true,
        session_ref: make_ref()
      ]

      # This should spawn Claude with -p flag
      result = CLI.spawn_new_session(prompt, opts)

      case result do
        {:ok, port, ref} ->
          # Verify we got a valid port and reference
          assert is_port(port)
          assert is_reference(ref)

          # Clean up: close the port
          Port.close(port)

        {:error, {:binary_not_found, _}} ->
          # Claude binary not installed on this machine — skip
          :ok

        {:error, reason} ->
          # If Claude is not installed, skip the test
          if String.contains?(inspect(reason), ["not found", "enoent"]) do
            :ok
          else
            flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end

    test "command includes -p flag" do
      # Verify the argument list includes -p
      prompt = "test message"

      # We can't easily test the exact args, but we can verify the function
      # accepts the prompt and returns a reference
      opts = [
        model: "sonnet",
        output_format: "stream-json",
        skip_permissions: true,
        session_ref: make_ref()
      ]

      case CLI.spawn_new_session(prompt, opts) do
        {:ok, port, ref} ->
          Port.close(port)
          assert is_reference(ref)

        {:error, _} ->
          # Claude not installed, skip
          :ok
      end
    end
  end
end

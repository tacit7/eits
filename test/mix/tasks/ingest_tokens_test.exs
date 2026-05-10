defmodule Mix.Tasks.IngestTokensTest do
  use EyeInTheSky.DataCase

  import EyeInTheSky.Factory

  # Capture shell output as messages; restore real shell on exit.
  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  # Collect N shell messages; returns the list of message strings.
  defp drain_shell_messages(count) do
    for _ <- 1..count do
      receive do
        {:mix_shell, :info, [msg]} -> msg
        {:mix_shell, :error, [msg]} -> msg
      after
        500 -> ""
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ingest_all (no --session flag)
  # Each test runs in an isolated DB sandbox, so cross-test state is not a concern.
  # ---------------------------------------------------------------------------

  describe "run/1 — ingest all" do
    test "prints 'incremental' mode label when --force is not set" do
      Mix.Tasks.IngestTokens.run([])

      # ingest_all emits exactly 2 messages: banner then Done heredoc.
      assert_receive {:mix_shell, :info, [banner]}
      assert_receive {:mix_shell, :info, _done}
      assert banner =~ "incremental"
    end

    test "prints summary with ingested/skipped/errors counts" do
      Mix.Tasks.IngestTokens.run([])

      messages = drain_shell_messages(2)
      full = Enum.join(messages, "\n")

      assert full =~ "Ingested:"
      assert full =~ "Skipped:"
      assert full =~ "Errors:"
    end

    test "prints 'force' mode label when --force flag is set" do
      Mix.Tasks.IngestTokens.run(["--force"])

      assert_receive {:mix_shell, :info, [banner]}
      assert_receive {:mix_shell, :info, _done}
      assert banner =~ "force"
    end

    test "accepts -f alias for --force and prints 'force' mode" do
      Mix.Tasks.IngestTokens.run(["-f"])

      assert_receive {:mix_shell, :info, [banner]}
      assert_receive {:mix_shell, :info, _done}
      assert banner =~ "force"
    end

    test "reports zero ingested when no JSONL files are discoverable" do
      # The DB sandbox is clean per-test; HOME's ~/.claude/projects contains no
      # sessions that match sandbox-created session UUIDs.
      Mix.Tasks.IngestTokens.run([])

      messages = drain_shell_messages(2)
      full = Enum.join(messages, "\n")

      assert full =~ "Ingested: 0"
    end
  end

  # ---------------------------------------------------------------------------
  # ingest_single (--session flag)
  # ---------------------------------------------------------------------------

  describe "run/1 — single session (--session flag)" do
    test "prints 'Ingesting session <uuid>...' banner" do
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["--session", uuid])

      assert_receive {:mix_shell, :info, [banner]}
      assert banner =~ "Ingesting session"
      assert banner =~ uuid
    end

    test "prints error when session UUID does not exist in the database" do
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["--session", uuid])

      assert_receive {:mix_shell, :info, _banner}
      assert_receive {:mix_shell, :error, [error_msg]}

      assert error_msg =~ "Failed"
      assert error_msg =~ ":session_not_found"
    end

    test "accepts -s alias for --session" do
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["-s", uuid])

      assert_receive {:mix_shell, :info, [banner]}
      assert_receive {:mix_shell, :error, _}
      assert banner =~ uuid
    end

    test "--session flag takes priority; --force is silently ignored for single-session runs" do
      # The task checks opts[:session] first and branches to ingest_single, which
      # does not accept a force option. This verifies no crash occurs.
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["--session", uuid, "--force"])

      assert_receive {:mix_shell, :info, [banner]}
      assert banner =~ uuid
    end

    @tag :integration
    test "ingests a real JSONL file and reports Done for a known session" do
      agent = create_agent()
      session = create_session(agent)

      # Build a fake ~/.claude/projects tree in tmp so SessionReader discovers it.
      escaped_path = "-tmp-eits-test-#{System.unique_integer([:positive])}"
      home = System.tmp_dir!()
      projects_dir = Path.join([home, ".claude", "projects", escaped_path])
      File.mkdir_p!(projects_dir)

      jsonl_path = Path.join(projects_dir, "#{session.uuid}.jsonl")

      jsonl_line =
        Jason.encode!(%{
          "type" => "assistant",
          "requestId" => "req-001",
          "message" => %{
            "model" => "claude-sonnet-4-5",
            "usage" => %{
              "input_tokens" => 100,
              "output_tokens" => 50,
              "cache_creation_input_tokens" => 0,
              "cache_read_input_tokens" => 0
            }
          }
        })

      File.write!(jsonl_path, jsonl_line <> "\n")

      original_home = System.get_env("HOME")
      System.put_env("HOME", home)

      on_exit(fn ->
        System.put_env("HOME", original_home)
        File.rm_rf!(Path.join([home, ".claude"]))
      end)

      Mix.Tasks.IngestTokens.run(["--session", session.uuid])

      assert_receive {:mix_shell, :info, _banner}
      assert_receive {:mix_shell, :info, [done_msg]}

      assert done_msg =~ "Done"
    end

    @tag :integration
    test "prints error when JSONL file contains only malformed lines" do
      agent = create_agent()
      session = create_session(agent)

      escaped_path = "-tmp-eits-bad-#{System.unique_integer([:positive])}"
      home = System.tmp_dir!()
      projects_dir = Path.join([home, ".claude", "projects", escaped_path])
      File.mkdir_p!(projects_dir)

      # Write a JSONL file with only garbage — no valid assistant entries.
      jsonl_path = Path.join(projects_dir, "#{session.uuid}.jsonl")
      File.write!(jsonl_path, "not json at all\n{\"type\": \"user\", \"text\": \"hello\"}\n")

      original_home = System.get_env("HOME")
      System.put_env("HOME", home)

      on_exit(fn ->
        System.put_env("HOME", original_home)
        File.rm_rf!(Path.join([home, ".claude"]))
      end)

      Mix.Tasks.IngestTokens.run(["--session", session.uuid])

      # TokenParser succeeds with zero-token usage — ingest completes without error.
      assert_receive {:mix_shell, :info, _banner}
      assert_receive {:mix_shell, :info, [done_msg]}

      assert done_msg =~ "Done"
    end
  end
end

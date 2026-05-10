defmodule Mix.Tasks.IngestTokensTest do
  @moduledoc """
  Tests for Mix.Tasks.IngestTokens.

  The task delegates all heavy lifting to EyeInTheSky.Metrics.TokenIngestion.
  Tests cover:
    - Banner output for incremental vs. force modes
    - Banner output for single-session mode
    - Error output when a session UUID cannot be resolved
    - Summary line presence after ingest_all
  """
  use EyeInTheSky.DataCase

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1 — ingest_all incremental mode (default)" do
    test "prints incremental mode banner" do
      Mix.Tasks.IngestTokens.run([])

      assert_receive {:mix_shell, :info, [banner]}
      assert banner =~ "incremental"
    end

    test "prints Done summary with Ingested/Skipped/Errors labels" do
      Mix.Tasks.IngestTokens.run([])

      # consume the banner message
      assert_receive {:mix_shell, :info, [_banner]}
      assert_receive {:mix_shell, :info, [summary]}
      assert summary =~ "Done"
      assert summary =~ "Ingested:"
      assert summary =~ "Skipped:"
      assert summary =~ "Errors:"
    end
  end

  describe "run/1 — ingest_all force mode (--force)" do
    test "prints force mode banner when --force is passed" do
      Mix.Tasks.IngestTokens.run(["--force"])

      assert_receive {:mix_shell, :info, [banner]}
      assert banner =~ "force"
    end

    test "prints force mode banner when -f shorthand is passed" do
      Mix.Tasks.IngestTokens.run(["-f"])

      assert_receive {:mix_shell, :info, [banner]}
      assert banner =~ "force"
    end

    test "prints Done summary after force ingest" do
      Mix.Tasks.IngestTokens.run(["--force"])

      assert_receive {:mix_shell, :info, [_banner]}
      assert_receive {:mix_shell, :info, [summary]}
      assert summary =~ "Done"
    end
  end

  describe "run/1 — single session mode (--session / -s)" do
    test "prints 'Ingesting session <uuid>' banner" do
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["--session", uuid])

      assert_receive {:mix_shell, :info, [banner]}
      assert banner =~ "Ingesting session"
      assert banner =~ uuid
    end

    test "prints failure message when session UUID is not in DB" do
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["--session", uuid])

      # banner first
      assert_receive {:mix_shell, :info, [_banner]}
      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "Failed"
    end

    test "prints failure message when -s shorthand is used with unknown UUID" do
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["-s", uuid])

      assert_receive {:mix_shell, :info, [_banner]}
      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "Failed"
    end

    test "prints 'session_not_found' in error for unknown UUID" do
      uuid = Ecto.UUID.generate()
      Mix.Tasks.IngestTokens.run(["--session", uuid])

      assert_receive {:mix_shell, :info, [_banner]}
      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "session_not_found"
    end
  end

  describe "run/1 — unknown/invalid flags are silently ignored" do
    test "unknown flags do not crash the task" do
      # OptionParser drops invalid strict flags into the _invalid list;
      # the task ignores them and falls through to ingest_all
      Mix.Tasks.IngestTokens.run(["--bogus-flag"])

      assert_receive {:mix_shell, :info, [banner]}
      assert banner =~ "incremental"
    end
  end
end

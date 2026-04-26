defmodule EyeInTheSky.Codex.CLITest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.CLI

  # ---------------------------------------------------------------------------
  # build_args/1 basics
  # ---------------------------------------------------------------------------

  describe "build_args/1 basics" do
    test "starts with exec subcommand" do
      args = CLI.build_args(prompt: "hello")
      assert List.first(args) == "exec"
    end

    test "always includes --json" do
      args = CLI.build_args(prompt: "hello")
      assert "--json" in args
    end

    test "prompt is the last positional argument" do
      args = CLI.build_args(prompt: "do something")
      assert List.last(args) == "do something"
    end

    test "no prompt produces args without trailing positional" do
      args = CLI.build_args([])
      assert "--json" in args
      refute nil in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 model flag
  # ---------------------------------------------------------------------------

  describe "build_args/1 model" do
    test "model produces -m flag" do
      args = CLI.build_args(prompt: "x", model: "o3")
      idx = Enum.find_index(args, &(&1 == "-m"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "o3"
    end

    test "nil model omits -m" do
      args = CLI.build_args(prompt: "x", model: nil)
      refute "-m" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 full_auto
  # ---------------------------------------------------------------------------

  describe "build_args/1 full_auto" do
    test "defaults to --dangerously-bypass-approvals-and-sandbox (bypass_sandbox default true)" do
      args = CLI.build_args(prompt: "x")
      assert "--dangerously-bypass-approvals-and-sandbox" in args
      refute "--full-auto" in args
    end

    test "full_auto: true with bypass_sandbox: false includes --full-auto" do
      args = CLI.build_args(prompt: "x", full_auto: true, bypass_sandbox: false)
      assert "--full-auto" in args
    end

    test "full_auto: false with bypass_sandbox: false omits --full-auto" do
      args = CLI.build_args(prompt: "x", full_auto: false, bypass_sandbox: false)
      refute "--full-auto" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 resume
  # ---------------------------------------------------------------------------

  describe "build_args/1 resume" do
    test "resume adds resume subcommand with thread_id" do
      args = CLI.build_args(prompt: "continue", resume: "thread-abc-123")
      assert Enum.take(args, 3) == ["exec", "resume", "thread-abc-123"]
    end

    test "no resume omits resume subcommand" do
      args = CLI.build_args(prompt: "x")
      refute "resume" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 nil filtering
  # ---------------------------------------------------------------------------

  describe "build_args/1 nil filtering" do
    test "nil values are filtered out" do
      args = CLI.build_args(prompt: "x", model: nil, resume: nil)
      refute "-m" in args
      refute "resume" in args
    end
  end

  # ---------------------------------------------------------------------------
  # build_args/1 arg order
  # ---------------------------------------------------------------------------

  describe "build_args/1 ordering" do
    test "exec is first, prompt is last" do
      args = CLI.build_args(prompt: "test prompt", model: "o3", full_auto: true)
      assert List.first(args) == "exec"
      assert List.last(args) == "test prompt"
    end

    test "flags appear between exec and prompt" do
      args = CLI.build_args(prompt: "test", model: "gpt-5.3-codex", resume: "tid")
      first = List.first(args)
      last = List.last(args)
      assert first == "exec"
      assert last == "test"

      middle = args |> Enum.drop(1) |> Enum.drop(-1)
      assert Enum.take(args, 3) == ["exec", "resume", "tid"]
      assert "--json" in middle
      assert "-m" in middle
      assert "resume" in middle
    end
  end

  # ---------------------------------------------------------------------------
  # clear_binary_cache/0
  # ---------------------------------------------------------------------------

  describe "clear_binary_cache/0" do
    test "returns :ok when no cache exists" do
      assert :ok = CLI.clear_binary_cache()
    end

    test "returns :ok after clearing" do
      # Call twice to ensure it's idempotent
      assert :ok = CLI.clear_binary_cache()
      assert :ok = CLI.clear_binary_cache()
    end
  end
end

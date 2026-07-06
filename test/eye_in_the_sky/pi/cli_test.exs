defmodule EyeInTheSky.Pi.CLITest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.CLI

  describe "build_env/1 (allowlist)" do
    test "explicitly UNSETS provider credentials ({key, false}), never forwards them" do
      System.put_env("OPENAI_API_KEY", "decoy-openai")
      System.put_env("ANTHROPIC_API_KEY", "decoy-anthropic")
      System.put_env("OPENROUTER_API_KEY", "decoy-openrouter")

      on_exit(fn ->
        Enum.each(~w(OPENAI_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY), &System.delete_env/1)
      end)

      env_map = Map.new(CLI.build_env([]), fn {k, v} -> {List.to_string(k), v} end)

      # Port.open's {:env, list} EXTENDS the inherited env; a var is only
      # removed by an explicit {key, false} entry. Absence would mean a leak.
      assert env_map["OPENAI_API_KEY"] == false
      assert env_map["ANTHROPIC_API_KEY"] == false
      assert env_map["OPENROUTER_API_KEY"] == false
    end

    test "forwards allowlisted base vars and EITS opts" do
      env = CLI.build_env(eits_session_uuid: "u-1", eits_project_id: 1, turn_id: "turn-9")

      env_map =
        for {k, v} <- env, v != false, into: %{}, do: {List.to_string(k), List.to_string(v)}

      assert env_map["HOME"] == System.get_env("HOME")
      assert env_map["PATH"] == System.get_env("PATH")
      assert env_map["EITS_SESSION_UUID"] == "u-1"
      assert env_map["EITS_PROJECT_ID"] == "1"
      assert env_map["EITS_PI_TURN_ID"] == "turn-9"
      assert Map.has_key?(env_map, "PI_PACKAGE_DIR")
    end

    test "real child process sees the allowlist env, not the server env" do
      # The definitive assertion: spawn an actual OS process through
      # spawn_harness (EITS_PI_HARNESS=/usr/bin/env prints its environment)
      # and verify the decoy credential is genuinely absent from the child.
      System.put_env("OPENAI_API_KEY", "decoy-child-leak")
      System.put_env("EITS_PI_HARNESS", "/usr/bin/env")

      on_exit(fn ->
        System.delete_env("OPENAI_API_KEY")
        System.delete_env("EITS_PI_HARNESS")
      end)

      {:ok, port, ref} = CLI.spawn_harness(caller: self(), project_path: System.tmp_dir!())

      child_env = collect_output(ref, "")

      refute child_env =~ "OPENAI_API_KEY",
             "provider credential leaked into the child process environment"

      refute child_env =~ "decoy-child-leak"
      assert child_env =~ "HOME="
      assert child_env =~ "PI_PACKAGE_DIR="

      if Port.info(port), do: CLI.cancel(port)
    end
  end

  defp collect_output(ref, acc) do
    receive do
      {:claude_output, ^ref, line} -> collect_output(ref, acc <> line <> "\n")
      {:claude_exit, ^ref, _} -> acc
    after
      5_000 -> acc
    end
  end

  describe "resolve_harness_command/0" do
    test "EITS_PI_HARNESS override wins" do
      System.put_env("EITS_PI_HARNESS", "/tmp/fake-harness")
      on_exit(fn -> System.delete_env("EITS_PI_HARNESS") end)
      assert {:ok, {"/tmp/fake-harness", []}} = CLI.resolve_harness_command()
    end

    test "falls back to bun + source when compiled binary is absent" do
      System.delete_env("EITS_PI_HARNESS")

      case CLI.resolve_harness_command() do
        {:ok, {exe, args}} ->
          assert String.ends_with?(exe, "eits-pi-harness") or String.contains?(exe, "bun")
          if String.contains?(exe, "bun"), do: assert([Path.expand("pi-harness/src/main.ts")] == args)

        {:error, reason} ->
          assert reason == {:pi_harness_not_found, hint: "run scripts/build-pi-harness.sh"}
      end
    end
  end
end

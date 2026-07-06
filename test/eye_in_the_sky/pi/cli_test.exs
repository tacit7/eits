defmodule EyeInTheSky.Pi.CLITest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.CLI

  describe "build_env/1 (allowlist)" do
    test "never forwards provider credentials, even when set in server env" do
      System.put_env("OPENAI_API_KEY", "decoy-openai")
      System.put_env("ANTHROPIC_API_KEY", "decoy-anthropic")
      System.put_env("OPENROUTER_API_KEY", "decoy-openrouter")

      on_exit(fn ->
        Enum.each(~w(OPENAI_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY), &System.delete_env/1)
      end)

      env_keys = CLI.build_env([]) |> Enum.map(fn {k, _v} -> List.to_string(k) end)

      refute "OPENAI_API_KEY" in env_keys
      refute "ANTHROPIC_API_KEY" in env_keys
      refute "OPENROUTER_API_KEY" in env_keys
    end

    test "forwards allowlisted base vars and EITS opts" do
      env = CLI.build_env(eits_session_uuid: "u-1", eits_project_id: 1, turn_id: "turn-9")
      env_map = Map.new(env, fn {k, v} -> {List.to_string(k), List.to_string(v)} end)

      assert env_map["HOME"] == System.get_env("HOME")
      assert env_map["PATH"] == System.get_env("PATH")
      assert env_map["EITS_SESSION_UUID"] == "u-1"
      assert env_map["EITS_PROJECT_ID"] == "1"
      assert env_map["EITS_PI_TURN_ID"] == "turn-9"
      assert Map.has_key?(env_map, "PI_PACKAGE_DIR")
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

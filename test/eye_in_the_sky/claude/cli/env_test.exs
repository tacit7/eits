defmodule EyeInTheSky.Claude.CLI.EnvTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.CLI.Env

  describe "blocked vars" do
    test "strips all RELEASE_* vars" do
      env =
        Env.build_from_map(
          %{
            "RELEASE_COMMAND" => "start",
            "RELEASE_ROOT" => "/some/path",
            "RELEASE_NODE" => "myapp",
            "HOME" => "/home/user"
          },
          []
        )

      keys = env_keys(env)
      refute "RELEASE_COMMAND" in keys
      refute "RELEASE_ROOT" in keys
      refute "RELEASE_NODE" in keys
      assert "HOME" in keys
    end

    test "strips BINDIR, ROOTDIR, EMU" do
      env =
        Env.build_from_map(
          %{
            "BINDIR" => "/app/_build/prod/rel/eye_in_the_sky/erts-16.1.2/bin",
            "ROOTDIR" => "/app/_build/prod/rel/eye_in_the_sky",
            "EMU" => "beam",
            "HOME" => "/home/user"
          },
          []
        )

      keys = env_keys(env)
      refute "BINDIR" in keys
      refute "ROOTDIR" in keys
      refute "EMU" in keys
      assert "HOME" in keys
    end

    test "strips ANTHROPIC_API_KEY by default and CLAUDE_CODE_ENTRYPOINT" do
      env =
        Env.build_from_map(
          %{
            "ANTHROPIC_API_KEY" => "sk-secret",
            "CLAUDE_CODE_ENTRYPOINT" => "cli",
            "HOME" => "/home/user"
          },
          []
        )

      keys = env_keys(env)
      refute "ANTHROPIC_API_KEY" in keys
      refute "CLAUDE_CODE_ENTRYPOINT" in keys
    end

    test "passes ANTHROPIC_API_KEY through when allow_anthropic_api_key: true" do
      env =
        Env.build_from_map(
          %{
            "ANTHROPIC_API_KEY" => "sk-secret",
            "HOME" => "/home/user"
          },
          allow_anthropic_api_key: true
        )

      assert env_get(env, "ANTHROPIC_API_KEY") == "sk-secret"
    end

    test "allow_anthropic_api_key: false still strips the key" do
      env =
        Env.build_from_map(
          %{"ANTHROPIC_API_KEY" => "sk-secret"},
          allow_anthropic_api_key: false
        )

      refute "ANTHROPIC_API_KEY" in env_keys(env)
    end

    test "strips CLAUDECODE" do
      env = Env.build_from_map(%{"CLAUDECODE" => "1", "HOME" => "/home/user"}, [])
      refute "CLAUDECODE" in env_keys(env)
    end

    test "strips SECRET_KEY_BASE" do
      env =
        Env.build_from_map(
          %{"SECRET_KEY_BASE" => "supersecretkey123", "HOME" => "/home/user"},
          []
        )

      refute "SECRET_KEY_BASE" in env_keys(env)
      assert "HOME" in env_keys(env)
    end

    test "strips DATABASE_URL" do
      env =
        Env.build_from_map(
          %{"DATABASE_URL" => "postgres://user:pass@localhost/eits_prod", "HOME" => "/home/user"},
          []
        )

      refute "DATABASE_URL" in env_keys(env)
      assert "HOME" in env_keys(env)
    end
  end

  describe "PATH sanitization" do
    test "removes release bin entry" do
      rel_bin = "/app/_build/prod/rel/eye_in_the_sky/bin"
      clean = "/usr/local/bin"
      env = Env.build_from_map(%{"PATH" => "#{rel_bin}:#{clean}"}, [])
      assert path_value(env) == clean
    end

    test "removes release ERTS bin entry" do
      erts_bin = "/app/_build/prod/rel/eye_in_the_sky/erts-16.1.2/bin"
      clean = "/usr/local/bin:/usr/bin"
      env = Env.build_from_map(%{"PATH" => "#{erts_bin}:#{clean}"}, [])
      assert path_value(env) == clean
    end

    test "removes any entry containing /erts-" do
      erts_entry = "/some/other/place/erts-27.0/bin"
      clean = "/usr/bin"
      env = Env.build_from_map(%{"PATH" => "#{erts_entry}:#{clean}"}, [])
      assert path_value(env) == clean
    end

    test "removes empty PATH segments" do
      env = Env.build_from_map(%{"PATH" => "/usr/bin::/usr/local/bin"}, [])
      refute String.contains?(path_value(env), "::")
    end

    test "multiple poisoned entries are all removed" do
      path =
        "/app/_build/prod/rel/eits/bin:/app/_build/prod/rel/eits/erts-16.1.2/bin:/usr/local/bin"

      env = Env.build_from_map(%{"PATH" => path}, [])
      assert path_value(env) == "/usr/local/bin"
    end

    test "clean PATH is not modified" do
      clean = "/usr/local/bin:/usr/bin:/home/user/.local/bin"
      env = Env.build_from_map(%{"PATH" => clean}, [])
      assert path_value(env) == clean
    end

    test "empty PATH string is excluded from env" do
      env = Env.build_from_map(%{"PATH" => ""}, [])
      assert Enum.find(env, fn {k, _} -> to_string(k) == "PATH" end) == nil
    end
  end

  describe "injected vars" do
    test "injects EITS_SESSION_ID when provided" do
      env = Env.build_from_map(%{}, eits_session_id: "abc-123")
      assert env_get(env, "EITS_SESSION_ID") == "abc-123"
    end

    test "injects EITS_WORKFLOW=1 by default" do
      env = Env.build_from_map(%{}, [])
      assert env_get(env, "EITS_WORKFLOW") == "1"
    end

    test "eits_workflow opt overrides default" do
      env = Env.build_from_map(%{}, eits_workflow: "0")
      assert env_get(env, "EITS_WORKFLOW") == "0"
    end

    test "blocked vars and injected vars coexist correctly" do
      env =
        Env.build_from_map(
          %{
            "RELEASE_COMMAND" => "start",
            "HOME" => "/home/user"
          },
          eits_session_id: "sess-1"
        )

      keys = env_keys(env)
      refute "RELEASE_COMMAND" in keys
      assert "HOME" in keys
      assert env_get(env, "EITS_SESSION_ID") == "sess-1"
    end
  end

  defp env_keys(env), do: Enum.map(env, fn {k, _} -> to_string(k) end)

  defp path_value(env) do
    case Enum.find(env, fn {k, _} -> to_string(k) == "PATH" end) do
      {_, v} -> to_string(v)
      nil -> nil
    end
  end

  defp env_get(env, key) do
    case Enum.find(env, fn {k, _} -> to_string(k) == key end) do
      {_, v} -> to_string(v)
      nil -> nil
    end
  end
end

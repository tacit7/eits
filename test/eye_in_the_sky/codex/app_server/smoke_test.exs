defmodule EyeInTheSky.Codex.AppServer.SmokeTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Codex.AppServer
  alias EyeInTheSky.Codex.SDK

  @moduletag :integration
  @moduletag timeout: 180_000

  if System.get_env("EITS_CODEX_APP_SERVER_SMOKE") != "1" do
    @moduletag :skip
  end

  test "real codex app-server completes a two-turn session and exposes hook context" do
    eits_session_id = "smoke-session-#{System.unique_integer([:positive])}"
    project_path = smoke_project!()
    hook_log = Path.join(project_path, "hook-events.ndjson")
    telemetry_ref = attach_hook_telemetry()
    codex_home = trusted_smoke_codex_home!(project_path)

    {first_ref, app_server_pid} =
      start_and_wait!(
        "Reply with exactly: EITS_APP_SERVER_SMOKE_ONE",
        eits_session_id,
        project_path,
        hook_log,
        codex_home: codex_home
      )

    assert_receive {:codex_session_id, ^first_ref, thread_id}, 120_000
    assert is_binary(thread_id)

    first_result = wait_for_result!(first_ref)
    assert first_result =~ "EITS_APP_SERVER_SMOKE_ONE"
    assert_receive {:claude_complete, ^first_ref, ^thread_id}, 120_000

    assert {:ok, hook_list} =
             AppServer.list_hooks(app_server_pid, [project_path],
               app_server_call_timeout_ms: 120_000
             )

    {second_ref, ^app_server_pid} =
      start_and_wait!(
        "Reply with exactly: EITS_APP_SERVER_SMOKE_TWO",
        eits_session_id,
        project_path,
        hook_log,
        codex_home: codex_home
      )

    second_result = wait_for_result!(second_ref)
    assert second_result =~ "EITS_APP_SERVER_SMOKE_TWO"
    assert_receive {:claude_complete, ^second_ref, ^thread_id}, 120_000

    assert_hook_context!(hook_log, hook_list, collect_hook_notifications(telemetry_ref))
  end

  defp start_and_wait!(prompt, eits_session_id, project_path, hook_log, extra_opts) do
    opts =
      Keyword.merge(
        [
          to: self(),
          project_path: project_path,
          codex_app_server: true,
          eits_session_uuid: "smoke-session-uuid",
          eits_session_id: eits_session_id,
          eits_agent_uuid: "smoke-agent-uuid",
          eits_agent_id: "smoke-agent-id",
          eits_project_id: "smoke-project-id",
          eits_url: "http://127.0.0.1:9/api/v1",
          eits_model: "smoke-model",
          app_server_call_timeout_ms: 120_000,
          smoke_hook_log: hook_log
        ],
        extra_opts
      )

    assert {:ok, ref, pid} = SDK.start(prompt, opts)
    assert is_pid(pid)
    {ref, pid}
  end

  defp wait_for_result!(ref) do
    receive do
      {:claude_message, ^ref, %Message{type: :result, content: content}} -> content
      {:claude_error, ^ref, reason} -> flunk("Codex app-server smoke failed: #{inspect(reason)}")
    after
      120_000 -> flunk("timed out waiting for Codex app-server smoke result")
    end
  end

  defp smoke_project! do
    root = Path.join(System.tmp_dir!(), "eits-codex-app-server-smoke-#{System.unique_integer()}")
    hooks_dir = Path.join(root, ".codex")
    script = Path.join(root, "record-hook.sh")

    File.mkdir_p!(hooks_dir)

    File.write!(
      Path.join(hooks_dir, "hooks.json"),
      Jason.encode!(hooks_json(script), pretty: true)
    )

    File.write!(script, """
    #!/bin/sh
    EVENT=$(jq -r '.hook_event_name // .event // "unknown"' 2>/dev/null || echo unknown)
    printf '{"event":"%s","session":"%s","agent":"%s","project":"%s"}\\n' "$EVENT" "$EITS_SESSION_UUID" "$EITS_AGENT_UUID" "$EITS_PROJECT_ID" >> "$EITS_CODEX_APP_SERVER_HOOK_LOG"
    exit 0
    """)

    File.chmod!(script, 0o755)
    root
  end

  defp hooks_json(script) do
    command = "EITS_CODEX_APP_SERVER_HOOK_LOG=\"$EITS_CODEX_APP_SERVER_HOOK_LOG\" #{script}"

    %{
      "description" => "Codex app-server smoke hooks for EITS tests.",
      "hooks" => %{
        "SessionStart" => [%{"hooks" => [hook_command(command)]}],
        "UserPromptSubmit" => [%{"hooks" => [hook_command(command)]}],
        "Stop" => [%{"hooks" => [hook_command(command)]}]
      }
    }
  end

  defp hook_command(command), do: %{"type" => "command", "command" => command, "timeout" => 5}

  defp trusted_smoke_codex_home!(project_path) do
    codex_home = Path.join(project_path, "codex-home")
    File.mkdir_p!(codex_home)
    link_codex_auth_file!(codex_home, "auth.json")
    link_optional_codex_auth_file!(codex_home, "installation_id")

    File.write!(Path.join(codex_home, "config.toml"), project_trust_config(project_path))

    owner_key = {:smoke_hook_probe, make_ref()}

    {:ok, pid} =
      AppServer.lookup_or_start(owner_key, project_path: project_path, codex_home: codex_home)

    try do
      assert {:ok, hook_list} =
               AppServer.list_hooks(pid, [project_path], app_server_call_timeout_ms: 120_000)

      hooks = hooks_from_list(hook_list)
      assert hooks != [], "trusted smoke project did not expose hooks through hooks/list"

      File.write!(
        Path.join(codex_home, "config.toml"),
        project_trust_config(project_path) <> "\n" <> trusted_hook_config(hooks)
      )

      codex_home
    after
      AppServer.stop_owner(owner_key)
    end
  end

  defp hooks_from_list(%{"data" => data}) when is_list(data) do
    Enum.flat_map(data, &hooks_from_list/1)
  end

  defp hooks_from_list(%{"hooks" => hooks}) when is_list(hooks), do: hooks
  defp hooks_from_list(_result), do: []

  defp project_trust_config(project_path) do
    """
    [features]
    hooks = true

    [projects."#{escape_config_string(realpath!(project_path))}"]
    trust_level = "trusted"
    """
  end

  defp realpath!(path) do
    case System.cmd("pwd", ["-P"], cd: path) do
      {realpath, 0} -> String.trim(realpath)
      {error, status} -> flunk("failed to resolve #{path}: #{inspect({status, error})}")
    end
  end

  defp trusted_hook_config(hooks) do
    state =
      hooks
      |> Enum.map(&trusted_hook_state_entry/1)
      |> Enum.join("\n\n")

    """
    #{state}
    """
  end

  defp trusted_hook_state_entry(%{"key" => key, "currentHash" => hash})
       when is_binary(key) and is_binary(hash) do
    """
    [hooks.state."#{escape_config_string(key)}"]
    trusted_hash = "#{escape_config_string(hash)}"
    """
  end

  defp trusted_hook_state_entry(hook) do
    flunk("hooks/list returned a hook without key/currentHash: #{inspect(hook)}")
  end

  defp escape_config_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace(~s("), ~s(\\"))
  end

  defp link_codex_auth_file!(codex_home, relative_path) do
    source = Path.join(Path.expand("~/.codex"), relative_path)

    unless File.exists?(source) do
      flunk("Codex app-server smoke requires #{relative_path} in ~/.codex")
    end

    File.ln_s!(source, Path.join(codex_home, relative_path))
  end

  defp link_optional_codex_auth_file!(codex_home, relative_path) do
    source = Path.join(Path.expand("~/.codex"), relative_path)

    if File.exists?(source) do
      File.ln_s!(source, Path.join(codex_home, relative_path))
    end
  end

  defp assert_hook_context!(hook_log, hook_list, hook_notifications) do
    if File.exists?(hook_log) do
      events =
        hook_log
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert Enum.any?(events, &(&1["session"] == "smoke-session-uuid"))
      assert Enum.any?(events, &(&1["agent"] == "smoke-agent-uuid"))
      assert Enum.any?(events, &(&1["project"] == "smoke-project-id"))
    else
      flunk("""
      Codex app-server did not write hook log; hook parity is not proven.

      hooks/list response: #{inspect(hook_list)}
      hook notifications: #{inspect(hook_notifications)}
      """)
    end
  end

  defp attach_hook_telemetry do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, ref}

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:eits, :codex, :app_server, :hook_started],
          [:eits, :codex, :app_server, :hook_completed]
        ],
        fn event, measurements, metadata, _config ->
          suffix = Enum.drop(event, 3)
          send(test_pid, {:app_server_hook_telemetry, ref, suffix, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    ref
  end

  defp collect_hook_notifications(ref, acc \\ []) do
    receive do
      {:app_server_hook_telemetry, ^ref, event, _measurements, metadata} ->
        collect_hook_notifications(ref, [{event, metadata} | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end

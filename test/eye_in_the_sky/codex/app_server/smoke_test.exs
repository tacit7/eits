defmodule EyeInTheSky.Codex.AppServer.SmokeTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.Message
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

    first_ref =
      start_and_wait!(
        "Reply with exactly: EITS_APP_SERVER_SMOKE_ONE",
        eits_session_id,
        project_path,
        hook_log
      )

    assert_receive {:codex_session_id, ^first_ref, thread_id}, 120_000
    assert is_binary(thread_id)

    first_result = wait_for_result!(first_ref)
    assert first_result =~ "EITS_APP_SERVER_SMOKE_ONE"
    assert_receive {:claude_complete, ^first_ref, ^thread_id}, 120_000

    second_ref =
      start_and_wait!(
        "Reply with exactly: EITS_APP_SERVER_SMOKE_TWO",
        eits_session_id,
        project_path,
        hook_log
      )

    second_result = wait_for_result!(second_ref)
    assert second_result =~ "EITS_APP_SERVER_SMOKE_TWO"
    assert_receive {:claude_complete, ^second_ref, ^thread_id}, 120_000

    assert_hook_context!(hook_log)
  end

  defp start_and_wait!(prompt, eits_session_id, project_path, hook_log, extra_opts \\ []) do
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
    ref
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

  defp assert_hook_context!(hook_log) do
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
      flunk("Codex app-server did not write hook log; hook parity is not proven")
    end
  end
end

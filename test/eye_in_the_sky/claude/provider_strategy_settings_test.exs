defmodule EyeInTheSky.Claude.ProviderStrategySettingsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ProviderStrategy.{Claude, Codex}

  @state %{
    provider_conversation_id: "conversation-id",
    project_path: "/tmp/project",
    eits_session_uuid: "session-uuid",
    session_id: 42,
    agent_id: 7,
    project_id: 1,
    worktree: nil
  }

  test "Claude settings override strategy defaults" do
    opts =
      Claude.build_opts(@state, %{
        extra_cli_opts: [skip_permissions: false, permission_mode: "plan"]
      })

    assert Keyword.fetch!(opts, :skip_permissions) == false
    assert Keyword.fetch!(opts, :permission_mode) == "plan"
  end

  test "Codex settings override strategy defaults" do
    opts =
      Codex.build_opts(@state, %{
        bypass_sandbox: false,
        extra_cli_opts: [full_auto: false, sandbox: "read-only", ask_for_approval: "never"]
      })

    assert Keyword.fetch!(opts, :bypass_sandbox) == false
    assert Keyword.fetch!(opts, :full_auto) == false
    assert Keyword.fetch!(opts, :sandbox) == "read-only"
    assert Keyword.fetch!(opts, :ask_for_approval) == "never"
  end

  test "Codex DM effort reaches both exec and app-server requests" do
    for effort <- ["low", "medium", "high", "xhigh"] do
      opts = Codex.build_opts(@state, %{effort_level: effort})

      thread = EyeInTheSky.Codex.AppServer.Protocol.thread_resume_request(1, "thread", opts)
      turn = EyeInTheSky.Codex.AppServer.Protocol.turn_start_request(2, "thread", "hello", opts)
      args = EyeInTheSky.Codex.CLI.build_args(opts ++ [resume: "thread", prompt: "hello"])

      assert thread["params"]["config"]["model_reasoning_effort"] == effort
      assert turn["params"]["effort"] == effort

      assert ["-c", ~s(model_reasoning_effort="#{effort}")] in Enum.chunk_every(
               args,
               2,
               1,
               :discard
             )
    end
  end
end

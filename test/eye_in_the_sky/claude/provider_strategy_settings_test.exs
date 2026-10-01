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
end

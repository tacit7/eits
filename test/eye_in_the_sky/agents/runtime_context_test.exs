defmodule EyeInTheSky.Agents.RuntimeContextTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Agents.RuntimeContext

  describe "build/3" do
    setup do
      {:ok, agent} =
        EyeInTheSky.Agents.create_agent(%{
          uuid: Ecto.UUID.generate(),
          agent_type: "claude",
          status: "running",
          description: "test agent"
        })

      {:ok, session} =
        EyeInTheSky.Sessions.create_session(%{
          uuid: Ecto.UUID.generate(),
          agent_id: agent.id,
          name: "test session",
          provider: "claude",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      %{session: session}
    end

    test "returns map with all expected keys", %{session: session} do
      ctx =
        RuntimeContext.build(session.id, "claude",
          model: "sonnet",
          effort_level: "high",
          channel_id: 42,
          thinking_budget: 10_000,
          max_budget_usd: 5.0,
          agent: "test-agent",
          eits_workflow: "1"
        )

      assert ctx.model == "sonnet"
      assert ctx.effort_level == "high"
      assert ctx.has_messages == false
      assert ctx.channel_id == 42
      assert ctx.thinking_budget == 10_000
      assert ctx.max_budget_usd == 5.0
      assert ctx.agent == "test-agent"
      assert ctx.eits_workflow == "1"
    end

    test "has_messages is false for fresh session", %{session: session} do
      ctx = RuntimeContext.build(session.id, "claude", [])
      assert ctx.has_messages == false
    end

    test "has_messages is true after inbound reply", %{session: session} do
      EyeInTheSky.Messages.create_message(%{
        session_id: session.id,
        direction: "inbound",
        provider: "claude",
        sender_role: "assistant",
        body: "Hello"
      })

      ctx = RuntimeContext.build(session.id, "claude", [])
      assert ctx.has_messages == true
    end

    test "missing opts default to nil", %{session: session} do
      ctx = RuntimeContext.build(session.id, "claude", [])

      assert ctx.model == nil
      assert ctx.effort_level == nil
      assert ctx.channel_id == nil
      assert ctx.thinking_budget == nil
      assert ctx.max_budget_usd == nil
      assert ctx.agent == nil
      assert ctx.eits_workflow == nil
    end

    test "unknown opts go into extra_cli_opts", %{session: session} do
      ctx =
        RuntimeContext.build(session.id, "claude",
          model: "sonnet",
          chrome: true,
          sandbox: true,
          permission_mode: "plan",
          add_dir: "/some/path",
          mcp_config: "./mcp.json",
          plugin_dir: "./plugins",
          settings_file: "./settings.json",
          max_turns: 5
        )

      assert Keyword.get(ctx.extra_cli_opts, :chrome) == true
      assert Keyword.get(ctx.extra_cli_opts, :sandbox) == true
      assert Keyword.get(ctx.extra_cli_opts, :permission_mode) == "plan"
      assert Keyword.get(ctx.extra_cli_opts, :add_dir) == "/some/path"
      assert Keyword.get(ctx.extra_cli_opts, :mcp_config) == "./mcp.json"
      assert Keyword.get(ctx.extra_cli_opts, :plugin_dir) == "./plugins"
      assert Keyword.get(ctx.extra_cli_opts, :settings_file) == "./settings.json"
      assert Keyword.get(ctx.extra_cli_opts, :max_turns) == 5
    end

    test "known keys are NOT in extra_cli_opts", %{session: session} do
      ctx =
        RuntimeContext.build(session.id, "claude",
          model: "sonnet",
          effort_level: "high",
          max_budget_usd: 2.0,
          chrome: true
        )

      refute Keyword.has_key?(ctx.extra_cli_opts, :model)
      refute Keyword.has_key?(ctx.extra_cli_opts, :effort_level)
      refute Keyword.has_key?(ctx.extra_cli_opts, :max_budget_usd)
      assert Keyword.get(ctx.extra_cli_opts, :chrome) == true
    end

    test "extra_cli_opts is empty list when no unknown keys", %{session: session} do
      ctx = RuntimeContext.build(session.id, "claude", model: "sonnet", effort_level: "high")
      assert ctx.extra_cli_opts == []
    end
  end
end

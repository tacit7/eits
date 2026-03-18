defmodule EyeInTheSkyWeb.Agents.RuntimeContextTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.Agents.RuntimeContext

  describe "build/3" do
    setup do
      {:ok, agent} =
        EyeInTheSkyWeb.Agents.create_agent(%{
          uuid: Ecto.UUID.generate(),
          agent_type: "claude",
          status: "running",
          description: "test agent"
        })

      {:ok, session} =
        EyeInTheSkyWeb.Sessions.create_session(%{
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
      EyeInTheSkyWeb.Messages.create_message(%{
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
  end
end

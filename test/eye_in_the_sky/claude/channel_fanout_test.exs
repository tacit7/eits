defmodule EyeInTheSky.Claude.ChannelFanoutTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ChannelFanout

  # ChannelFanout integrates with DB (Channels, Sessions, Messages, AgentManager).
  # Unit tests verify only the module's public interface contracts.
  # Full integration tests would require a DB sandbox and mocks.

  @exported ChannelFanout.__info__(:functions)

  describe "fanout_all public API" do
    test "exports fanout_all with arity 3 (default content_blocks and message_id)" do
      assert {:fanout_all, 3} in @exported
    end

    test "exports fanout_all with arity 4 (default message_id only)" do
      assert {:fanout_all, 4} in @exported
    end

    test "exports fanout_all with arity 5 (all args)" do
      assert {:fanout_all, 5} in @exported
    end
  end

  describe "fanout_mentions_only public API" do
    test "exports fanout_mentions_only with arity 3 (default message_id)" do
      assert {:fanout_mentions_only, 3} in @exported
    end

    test "exports fanout_mentions_only with arity 4 (all args)" do
      assert {:fanout_mentions_only, 4} in @exported
    end
  end
end

defmodule EyeInTheSky.Claude.ChannelFanoutModelTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Claude.ChannelFanout
  alias EyeInTheSky.Factory

  describe "model_opts/1" do
    test "uses the target session's own model, not the global default" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent, %{model: "claude-opus-5-5"})

      assert ChannelFanout.model_opts(session.id) == [model: "claude-opus-5-5"]
    end

    test "passes no model when the session has none" do
      agent = Factory.create_agent()
      session = Factory.create_session(agent)

      assert ChannelFanout.model_opts(session.id) == []
    end

    test "passes no model for an unknown session" do
      assert ChannelFanout.model_opts(-1) == []
    end
  end
end

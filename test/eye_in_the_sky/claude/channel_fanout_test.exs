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

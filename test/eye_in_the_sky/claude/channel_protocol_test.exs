defmodule EyeInTheSky.Claude.ChannelProtocolTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ChannelProtocol

  describe "parse_routing/2" do
    test "returns :direct when session_id is mentioned by @id" do
      {mode, mentioned_ids, mention_all} = ChannelProtocol.parse_routing("Hey @42 check this", 42)

      assert mode == :direct
      assert 42 in mentioned_ids
      assert mention_all == false
    end

    test "returns :ambient when session_id is not mentioned" do
      {mode, mentioned_ids, mention_all} =
        ChannelProtocol.parse_routing("Hey @42 check this", 99)

      assert mode == :ambient
      assert 42 in mentioned_ids
      assert 99 not in mentioned_ids
      assert mention_all == false
    end

    test "returns :broadcast when @all is used" do
      {mode, _mentioned_ids, mention_all} =
        ChannelProtocol.parse_routing("@all please respond", 42)

      assert mode == :broadcast
      assert mention_all == true
    end

    test "@all is case-insensitive" do
      {mode, _, mention_all} = ChannelProtocol.parse_routing("@ALL respond now", 1)
      assert mode == :broadcast
      assert mention_all == true

      {mode2, _, mention_all2} = ChannelProtocol.parse_routing("@All respond now", 1)
      assert mode2 == :broadcast
      assert mention_all2 == true
    end

    test "@all takes priority over direct mention" do
      {mode, mentioned_ids, mention_all} =
        ChannelProtocol.parse_routing("@all @42 do something", 42)

      assert mode == :broadcast
      assert 42 in mentioned_ids
      assert mention_all == true
    end

    test "extracts multiple mentioned IDs" do
      {_mode, mentioned_ids, _mention_all} =
        ChannelProtocol.parse_routing("@10 @20 @30 collaborate", 99)

      assert Enum.sort(mentioned_ids) == [10, 20, 30]
    end

    test "deduplicates mentioned IDs" do
      {_mode, mentioned_ids, _mention_all} =
        ChannelProtocol.parse_routing("@10 @10 @10 hello", 99)

      assert mentioned_ids == [10]
    end

    test "no mentions returns :ambient with empty mentioned list" do
      {mode, mentioned_ids, mention_all} =
        ChannelProtocol.parse_routing("Just a regular message", 42)

      assert mode == :ambient
      assert mentioned_ids == []
      assert mention_all == false
    end

    test "handles @all as a word boundary (not @allison)" do
      {_mode, _mentioned_ids, mention_all} =
        ChannelProtocol.parse_routing("Hey @allison", 1)

      # @all\b should NOT match @allison
      assert mention_all == false
    end
  end

  describe "build_prompt/2" do
    test "direct mode includes direct instruction and message" do
      prompt = ChannelProtocol.build_prompt(:direct, "Hello agent")
      assert prompt =~ "directly mentioned"
      assert prompt =~ "Hello agent"
    end

    test "broadcast mode includes broadcast instruction and message" do
      prompt = ChannelProtocol.build_prompt(:broadcast, "Everyone respond")
      assert prompt =~ "broadcast"
      assert prompt =~ "Everyone respond"
    end

    test "ambient mode includes ambient instruction and message" do
      prompt = ChannelProtocol.build_prompt(:ambient, "General chat")
      assert prompt =~ "[NO_RESPONSE]"
      assert prompt =~ "General chat"
    end

    test "message body is appended after instruction" do
      prompt = ChannelProtocol.build_prompt(:direct, "test body")
      assert prompt =~ "Message: test body"
    end
  end

  describe "skip?/2" do
    test "returns true when member is the sender" do
      assert ChannelProtocol.skip?(42, 42) == true
    end

    test "returns false when member is not the sender" do
      assert ChannelProtocol.skip?(42, 99) == false
    end
  end
end

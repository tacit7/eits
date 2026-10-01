defmodule EyeInTheSky.Codex.AppServer.TurnBufferTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Codex.AppServer.TurnBuffer

  test "streams deltas and preserves agent message item boundaries" do
    buffer = TurnBuffer.new()

    {buffer, [delta]} =
      TurnBuffer.apply_notification(buffer, "item/agentMessage/delta", %{
        "itemId" => "msg-1",
        "delta" => "first"
      })

    assert %Message{type: :text, content: "first", delta: true} = delta

    {buffer, messages} =
      TurnBuffer.apply_notification(buffer, "item/agentMessage/delta", %{
        "itemId" => "msg-2",
        "delta" => "second"
      })

    assert [
             %Message{type: :text, content: "first", delta: false},
             %Message{type: :text, content: "second", delta: true}
           ] = messages

    {buffer, messages} =
      TurnBuffer.apply_notification(buffer, "item/completed", %{
        "item" => %{"id" => "msg-2", "type" => "agentMessage"}
      })

    assert [%Message{type: :text, content: "second", delta: false}] = messages
    assert TurnBuffer.result_text(buffer) == "firstsecond"
  end

  test "drains reasoning separately from result text" do
    buffer = TurnBuffer.new()

    {buffer, _} =
      TurnBuffer.apply_notification(buffer, "item/reasoning/textDelta", %{
        "itemId" => "reason-1",
        "delta" => "thinking"
      })

    {buffer, messages} = TurnBuffer.drain(buffer)

    assert [%Message{type: :thinking, content: "thinking", delta: false}] = messages
    assert TurnBuffer.result_text(buffer) == nil
  end
end

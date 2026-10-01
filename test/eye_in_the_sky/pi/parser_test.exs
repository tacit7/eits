defmodule EyeInTheSky.Pi.ParserTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Pi.Parser

  test "response envelope is a protocol event" do
    line =
      ~s({"id":"pi-1","type":"response","command":"initialize","success":true,"data":{"version":"0.74.0","protocolVersion":1}})

    assert {:protocol, %{"type" => "response", "id" => "pi-1", "success" => true}} =
             Parser.parse_stream_line(line)
  end

  test "ready is a protocol event" do
    line =
      ~s({"type":"ready","sessionId":"abc-123","sessionFile":"/x/y","model":"openrouter/qwen/qwen3-coder"})

    assert {:protocol, %{"type" => "ready", "sessionId" => "abc-123"}} =
             Parser.parse_stream_line(line)
  end

  test "assistant_delta becomes a delta text message" do
    assert {:ok, %Message{type: :text, content: "hel", delta: true}} =
             Parser.parse_stream_line(~s({"type":"assistant_delta","delta":"hel"}))
  end

  test "thinking_delta becomes a delta thinking message" do
    assert {:ok, %Message{type: :thinking, content: "hmm", delta: true}} =
             Parser.parse_stream_line(~s({"type":"thinking_delta","delta":"hmm"}))
  end

  test "tool_update start becomes a partial tool_use" do
    line =
      ~s({"type":"tool_update","phase":"start","toolCallId":"t1","toolName":"bash","args":{"command":"ls"}})

    assert {:ok,
            %Message{
              type: :tool_use,
              content: %{name: "bash", input: %{"command" => "ls"}},
              metadata: %{partial: true, tool_call_id: "t1"}
            }} =
             Parser.parse_stream_line(line)
  end

  test "tool_result becomes a completed tool_use" do
    line =
      ~s({"type":"tool_result","toolCallId":"t1","toolName":"bash","result":"ok\\n","isError":false})

    assert {:ok,
            %Message{
              type: :tool_use,
              content: %{name: "bash", input: %{"result" => "ok\n", "isError" => false}},
              metadata: %{tool_call_id: "t1"}
            }} =
             Parser.parse_stream_line(line)
  end

  test "turn_end becomes a result with usage" do
    line =
      ~s({"type":"turn_end","totalCostUsd":0.012,"durationMs":5400,"aggregate":{"inputTokens":100,"outputTokens":50,"cacheReadTokens":0,"cacheCreationTokens":0,"totalTokens":150}})

    assert {:result, data} = Parser.parse_stream_line(line)
    assert data.input_tokens == 100
    assert data.output_tokens == 50
    assert data.total_cost_usd == 0.012
    assert data.duration_ms == 5400
    assert data.usage["totalTokens"] == 150
  end

  test "turn_end without aggregate still yields a result" do
    assert {:result, data} = Parser.parse_stream_line(~s({"type":"turn_end"}))
    assert data.input_tokens == 0
  end

  test "turn_error is a protocol event (sticky-error handling is SDK's job)" do
    assert {:protocol, %{"type" => "turn_error", "error" => "rate limited"}} =
             Parser.parse_stream_line(~s({"type":"turn_error","error":"rate limited"}))
  end

  test "tool_request is a protocol event (SDK auto-denies in Phase 1)" do
    line =
      ~s({"type":"tool_request","requestId":"r1","toolCallId":"t2","kind":"commandExecution","input":{"command":"rm -rf /"}})

    assert {:protocol, %{"type" => "tool_request", "requestId" => "r1"}} =
             Parser.parse_stream_line(line)
  end

  test "exit event is a protocol event" do
    assert {:protocol, %{"type" => "exit"}} =
             Parser.parse_stream_line(~s({"type":"exit","error":"fatal"}))
  end

  test "top-level error event is an error" do
    assert {:error, {:pi_error, "bad things"}} =
             Parser.parse_stream_line(~s({"type":"error","error":"bad things"}))
  end

  test "unknown event types are skipped (forward compat)" do
    assert :skip = Parser.parse_stream_line(~s({"type":"telemetry_v9","payload":1}))
  end

  test "malformed json and blank lines are skipped" do
    assert :skip = Parser.parse_stream_line("not json {")
    assert :skip = Parser.parse_stream_line("   ")
  end

  test "compaction events become status text messages" do
    assert {:ok, %Message{type: :text}} =
             Parser.parse_stream_line(~s({"type":"compaction_start","reason":"context"}))

    assert {:ok, %Message{type: :text}} =
             Parser.parse_stream_line(
               ~s({"type":"compaction_end","reason":"context","aborted":false,"willRetry":false})
             )
  end
end

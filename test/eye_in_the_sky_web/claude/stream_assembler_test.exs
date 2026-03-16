defmodule EyeInTheSkyWeb.Claude.StreamAssemblerTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Claude.{Message, StreamAssembler}

  describe "new/0" do
    test "returns empty stream state" do
      stream = StreamAssembler.new()
      assert stream.buffer == ""
      assert stream.tool_id == nil
      assert stream.tool_name == nil
      assert stream.tool_input == ""
    end
  end

  describe "reset/1" do
    test "clears all fields back to defaults" do
      stream = %StreamAssembler{
        buffer: "some text",
        tool_id: "tool-1",
        tool_name: "Read",
        tool_input: "{\"path\":"
      }

      assert StreamAssembler.reset(stream) == StreamAssembler.new()
    end
  end

  describe "buffer/1" do
    test "returns the current buffer" do
      stream = %StreamAssembler{buffer: "hello world"}
      assert StreamAssembler.buffer(stream) == "hello world"
    end
  end

  describe "handle_message/2 - text deltas" do
    test "accumulates text delta into buffer and emits stream_delta event" do
      stream = StreamAssembler.new()
      msg = Message.text("hello ", true)

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == "hello "
      assert events == [{:stream_delta, :text, "hello "}]
    end

    test "appends consecutive text deltas" do
      stream = StreamAssembler.new()

      {stream, _} = StreamAssembler.handle_message(stream, Message.text("hello ", true))
      {stream, events} = StreamAssembler.handle_message(stream, Message.text("world", true))

      assert stream.buffer == "hello world"
      assert events == [{:stream_delta, :text, "world"}]
    end
  end

  describe "handle_message/2 - text replacement" do
    test "replaces buffer and emits stream_replace event" do
      stream = %StreamAssembler{buffer: "old text"}
      msg = %Message{type: :text, content: "new text", delta: false}

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == "new text"
      assert events == [{:stream_replace, :text, "new text"}]
    end

    test "ignores empty text replacement" do
      stream = StreamAssembler.new()
      msg = %Message{type: :text, content: "", delta: false}

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == ""
      assert events == []
    end
  end

  describe "handle_message/2 - tool use" do
    test "tool start sets tool tracking fields and emits tool_use event" do
      stream = StreamAssembler.new()

      msg = %Message{
        type: :tool_use,
        content: %{name: "Read"},
        delta: false,
        metadata: %{id: "tool-123"}
      }

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.tool_id == "tool-123"
      assert stream.tool_name == "Read"
      assert stream.tool_input == ""
      assert events == [{:stream_delta, :tool_use, "Read"}]
    end

    test "tool use with string name emits tool_use event" do
      stream = StreamAssembler.new()
      msg = %Message{type: :tool_use, content: "Write", delta: false, metadata: %{}}

      {_stream, events} = StreamAssembler.handle_message(stream, msg)

      assert events == [{:stream_delta, :tool_use, "Write"}]
    end
  end

  describe "handle_message/2 - thinking" do
    test "thinking delta emits stream_delta thinking event" do
      stream = StreamAssembler.new()
      msg = %Message{type: :thinking, content: nil, delta: true}

      {_stream, events} = StreamAssembler.handle_message(stream, msg)

      assert events == [{:stream_delta, :thinking, nil}]
    end

    test "thinking block emits stream_replace thinking event" do
      stream = StreamAssembler.new()
      msg = %Message{type: :thinking, content: "Let me think about this...", delta: false}

      {_stream, events} = StreamAssembler.handle_message(stream, msg)

      assert events == [{:stream_replace, :thinking, "Let me think about this..."}]
    end

    test "empty thinking block emits no events" do
      stream = StreamAssembler.new()
      msg = %Message{type: :thinking, content: "", delta: false}

      {_stream, events} = StreamAssembler.handle_message(stream, msg)

      assert events == []
    end
  end

  describe "handle_message/2 - unknown types" do
    test "unrecognized message type emits no events and doesn't change buffer" do
      stream = %StreamAssembler{buffer: "existing"}
      msg = %Message{type: :usage, content: %{input_tokens: 10, output_tokens: 5}}

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == "existing"
      assert events == []
    end
  end

  describe "handle_tool_delta/2" do
    test "accumulates tool input JSON" do
      stream = %StreamAssembler{tool_id: "t1", tool_name: "Read", tool_input: ""}

      {stream, events} = StreamAssembler.handle_tool_delta(stream, "{\"path\":")
      assert stream.tool_input == "{\"path\":"
      assert events == []

      {stream, events} = StreamAssembler.handle_tool_delta(stream, "\"/foo\"}")
      assert stream.tool_input == "{\"path\":\"/foo\"}"
      assert events == []
    end
  end

  describe "handle_tool_block_stop/1" do
    test "decodes valid JSON and emits stream_tool_input event" do
      stream = %StreamAssembler{
        tool_id: "t1",
        tool_name: "Read",
        tool_input: "{\"path\":\"/foo/bar.ex\"}"
      }

      {stream, events} = StreamAssembler.handle_tool_block_stop(stream)

      assert stream.tool_id == nil
      assert stream.tool_name == nil
      assert stream.tool_input == ""
      assert events == [{:stream_tool_input, "Read", %{"path" => "/foo/bar.ex"}}]
    end

    test "wraps invalid JSON in raw map" do
      stream = %StreamAssembler{
        tool_id: "t1",
        tool_name: "Bash",
        tool_input: "not valid json"
      }

      {stream, events} = StreamAssembler.handle_tool_block_stop(stream)

      assert stream.tool_id == nil
      assert [{:stream_tool_input, "Bash", %{raw: "not valid json"}}] = events
    end

    test "no-ops when no tool is active" do
      stream = StreamAssembler.new()

      {stream, events} = StreamAssembler.handle_tool_block_stop(stream)

      assert stream == StreamAssembler.new()
      assert events == []
    end
  end

  describe "full tool lifecycle" do
    test "start → deltas → stop produces correct final event" do
      stream = StreamAssembler.new()

      # Tool start
      start_msg = %Message{
        type: :tool_use,
        content: %{name: "Edit"},
        delta: false,
        metadata: %{id: "tool-42"}
      }

      {stream, _} = StreamAssembler.handle_message(stream, start_msg)
      assert stream.tool_id == "tool-42"

      # Input deltas
      {stream, _} = StreamAssembler.handle_tool_delta(stream, "{\"old\":")
      {stream, _} = StreamAssembler.handle_tool_delta(stream, "\"foo\",\"new\":")
      {stream, _} = StreamAssembler.handle_tool_delta(stream, "\"bar\"}")

      # Block stop
      {stream, events} = StreamAssembler.handle_tool_block_stop(stream)

      assert stream.tool_id == nil
      assert events == [{:stream_tool_input, "Edit", %{"old" => "foo", "new" => "bar"}}]
    end
  end
end

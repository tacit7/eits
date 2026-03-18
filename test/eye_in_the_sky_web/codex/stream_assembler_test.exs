defmodule EyeInTheSkyWeb.Codex.StreamAssemblerTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Claude.Message
  alias EyeInTheSkyWeb.Codex.StreamAssembler

  describe "new/0" do
    test "returns empty stream state" do
      stream = StreamAssembler.new()
      assert stream.buffer == ""
      assert stream.tool_name == nil
      assert stream.last_tool == nil
    end
  end

  describe "reset/1" do
    test "clears all fields back to defaults" do
      stream = %StreamAssembler{
        buffer: "some text",
        tool_name: "command_execution",
        last_tool: %{name: "command_execution"}
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

  describe "handle_message/2 - complete text block" do
    test "replaces buffer and emits stream_replace event" do
      stream = StreamAssembler.new()
      msg = Message.text("full response text", false)

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == "full response text"
      assert events == [{:stream_replace, :text, "full response text"}]
    end

    test "replaces previous buffer on new text block" do
      stream = %StreamAssembler{buffer: "old text"}
      msg = Message.text("new text", false)

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == "new text"
      assert events == [{:stream_replace, :text, "new text"}]
    end

    test "ignores empty text block" do
      stream = StreamAssembler.new()
      msg = Message.text("", false)

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == ""
      assert events == []
    end
  end

  describe "handle_message/2 - text delta (safety)" do
    test "appends delta to buffer and emits replace with full buffer" do
      stream = %StreamAssembler{buffer: "hello "}
      msg = Message.text("world", true)

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == "hello world"
      assert events == [{:stream_replace, :text, "hello world"}]
    end
  end

  describe "handle_message/2 - thinking" do
    test "complete thinking block emits stream_replace thinking event" do
      stream = StreamAssembler.new()
      msg = Message.thinking("reasoning about the problem", false)

      {_stream, events} = StreamAssembler.handle_message(stream, msg)

      assert events == [{:stream_replace, :thinking, "reasoning about the problem"}]
    end

    test "empty thinking block emits no events" do
      stream = StreamAssembler.new()
      msg = Message.thinking("", false)

      {_stream, events} = StreamAssembler.handle_message(stream, msg)

      assert events == []
    end
  end

  describe "handle_message/2 - tool use partial (item.started)" do
    test "command_execution partial emits tool_use and tool_input with command" do
      stream = StreamAssembler.new()

      msg = %Message{
        type: :tool_use,
        content: %{name: "command_execution", input: %{command: "mix test"}},
        delta: false,
        metadata: %{partial: true}
      }

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.tool_name == "command_execution"
      assert {:stream_delta, :tool_use, "command_execution"} in events
      assert {:stream_tool_input, "command_execution", %{command: "mix test"}} in events
    end

    test "web_search partial emits tool_use only" do
      stream = StreamAssembler.new()

      msg = %Message{
        type: :tool_use,
        content: %{name: "web_search", input: %{query: "elixir docs"}},
        delta: false,
        metadata: %{partial: true}
      }

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.tool_name == "web_search"
      assert events == [{:stream_delta, :tool_use, "web_search"}]
    end
  end

  describe "handle_message/2 - tool use complete (item.completed)" do
    test "command_execution complete emits tool_use and tool_input" do
      stream = StreamAssembler.new()

      input = %{command: "mix test", exit_code: 0, output: "3 tests, 0 failures"}

      msg = %Message{
        type: :tool_use,
        content: %{name: "command_execution", input: input},
        delta: false,
        metadata: %{}
      }

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.tool_name == "command_execution"
      assert stream.last_tool == %{name: "command_execution", input: input}
      assert {:stream_delta, :tool_use, "command_execution"} in events
      assert {:stream_tool_input, "command_execution", ^input} = List.last(events)
    end

    test "file_changes complete emits tool events" do
      stream = StreamAssembler.new()

      input = %{type: "file_changes", files: ["lib/foo.ex"]}

      msg = %Message{
        type: :tool_use,
        content: %{name: "file_changes", input: input},
        delta: false,
        metadata: %{}
      }

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.tool_name == "file_changes"
      assert {:stream_delta, :tool_use, "file_changes"} in events
      assert {:stream_tool_input, "file_changes", ^input} = List.last(events)
    end
  end

  describe "handle_message/2 - tool use string fallback" do
    test "string tool name emits tool_use event" do
      stream = StreamAssembler.new()
      msg = %Message{type: :tool_use, content: "unknown_tool", delta: false, metadata: %{}}

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.tool_name == "unknown_tool"
      assert events == [{:stream_delta, :tool_use, "unknown_tool"}]
    end
  end

  describe "handle_message/2 - unknown types" do
    test "unrecognized message type emits no events" do
      stream = %StreamAssembler{buffer: "existing"}
      msg = %Message{type: :usage, content: %{input_tokens: 10, output_tokens: 5}}

      {stream, events} = StreamAssembler.handle_message(stream, msg)

      assert stream.buffer == "existing"
      assert events == []
    end

    test "result message emits no events" do
      stream = StreamAssembler.new()
      msg = Message.result("final text", %{session_id: "abc"})

      {_stream, events} = StreamAssembler.handle_message(stream, msg)

      assert events == []
    end
  end

  describe "handle_tool_delta/2" do
    test "is a no-op for Codex (returns unchanged stream)" do
      stream = StreamAssembler.new()

      {new_stream, events} = StreamAssembler.handle_tool_delta(stream, "{\"path\":")

      assert new_stream == stream
      assert events == []
    end
  end

  describe "handle_tool_block_stop/1" do
    test "is a no-op for Codex" do
      stream = %StreamAssembler{tool_name: "command_execution"}

      {new_stream, events} = StreamAssembler.handle_tool_block_stop(stream)

      assert new_stream == stream
      assert events == []
    end
  end

  describe "full Codex turn lifecycle" do
    test "thinking → tool start → tool complete → text → reset" do
      stream = StreamAssembler.new()

      # 1. Reasoning item
      {stream, events} =
        StreamAssembler.handle_message(stream, Message.thinking("Let me check the tests", false))

      assert events == [{:stream_replace, :thinking, "Let me check the tests"}]

      # 2. Command started (partial)
      cmd_start = %Message{
        type: :tool_use,
        content: %{name: "command_execution", input: %{command: "mix test"}},
        delta: false,
        metadata: %{partial: true}
      }

      {stream, events} = StreamAssembler.handle_message(stream, cmd_start)
      assert {:stream_delta, :tool_use, "command_execution"} in events

      # 3. Command completed
      cmd_done = %Message{
        type: :tool_use,
        content: %{
          name: "command_execution",
          input: %{command: "mix test", exit_code: 0, output: "OK"}
        },
        delta: false,
        metadata: %{}
      }

      {stream, events} = StreamAssembler.handle_message(stream, cmd_done)
      assert {:stream_tool_input, "command_execution", %{exit_code: 0}} = List.last(events)

      # 4. Agent message
      {stream, events} =
        StreamAssembler.handle_message(stream, Message.text("All tests pass.", false))

      assert stream.buffer == "All tests pass."
      assert events == [{:stream_replace, :text, "All tests pass."}]

      # 5. Reset
      stream = StreamAssembler.reset(stream)
      assert stream == StreamAssembler.new()
    end
  end
end

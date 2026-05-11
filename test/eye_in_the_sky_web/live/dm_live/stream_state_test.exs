defmodule EyeInTheSkyWeb.DmLive.StreamStateTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSkyWeb.DmLive.StreamState

  # Helper to build a bare socket with assigns
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}}

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns)
    }
  end

  describe "handle_stream_delta/3" do
    test "appends text to stream_content for :text type" do
      socket = build_socket(%{stream_content: "Hello ", show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_delta(:text, "world", socket)

      assert result.assigns.stream_content == "Hello world"
    end

    test "accumulates multiple text deltas" do
      socket = build_socket(%{stream_content: "", show_live_stream: true})

      {:noreply, result1} = StreamState.handle_stream_delta(:text, "Hello ", socket)
      {:noreply, result2} = StreamState.handle_stream_delta(:text, "world", result1)

      assert result2.assigns.stream_content == "Hello world"
    end

    test "sets stream_tool for :tool_use type" do
      socket = build_socket(%{stream_tool: nil, show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_delta(:tool_use, "command_execution", socket)

      assert result.assigns.stream_tool == "Bash"
    end

    test "maps tool names correctly" do
      socket = build_socket(%{stream_tool: nil, show_live_stream: true})

      {:noreply, result1} = StreamState.handle_stream_delta(:tool_use, "web_search", socket)
      assert result1.assigns.stream_tool == "WebSearch"

      {:noreply, result2} = StreamState.handle_stream_delta(:tool_use, "web_searches", result1)
      assert result2.assigns.stream_tool == "WebSearch"

      {:noreply, result3} = StreamState.handle_stream_delta(:tool_use, "mcp_tool_call", result2)
      assert result3.assigns.stream_tool == "MCP Tool"
    end

    test "handles unknown tool names by returning the name as-is" do
      socket = build_socket(%{stream_tool: nil, show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_delta(:tool_use, "custom_tool", socket)

      assert result.assigns.stream_tool == "custom_tool"
    end

    test "ignores :thinking type deltas" do
      socket = build_socket(%{stream_thinking: nil, show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_delta(:thinking, "some thinking", socket)

      # Socket should be unchanged
      assert result.assigns == socket.assigns
    end

    test "ignores unknown types" do
      socket = build_socket(%{stream_content: "original", show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_delta(:unknown, "data", socket)

      # Socket should be unchanged
      assert result.assigns == socket.assigns
    end

    test "works correctly when show_live_stream is false" do
      socket = build_socket(%{stream_content: "hello", show_live_stream: false})

      {:noreply, result} = StreamState.handle_stream_delta(:text, " world", socket)

      # Should still append even if show_live_stream is false
      assert result.assigns.stream_content == "hello world"
    end
  end

  describe "handle_stream_replace/3" do
    test "replaces text for :text type" do
      socket = build_socket(%{stream_content: "old content", show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_replace(:text, "new content", socket)

      assert result.assigns.stream_content == "new content"
    end

    test "replaces thinking for :thinking type" do
      socket = build_socket(%{stream_thinking: "old thinking", show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_replace(:thinking, "new thinking", socket)

      assert result.assigns.stream_thinking == "new thinking"
    end

    test "handles empty text replacements" do
      socket = build_socket(%{stream_content: "something", show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_replace(:text, "", socket)

      assert result.assigns.stream_content == ""
    end

    test "handles large text replacements" do
      large_text = String.duplicate("a", 10000)
      socket = build_socket(%{stream_content: "short", show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_replace(:text, large_text, socket)

      assert result.assigns.stream_content == large_text
      assert String.length(result.assigns.stream_content) == 10000
    end

    test "ignores unknown types in replace" do
      socket = build_socket(%{stream_content: "original", show_live_stream: true})

      {:noreply, result} = StreamState.handle_stream_replace(:unknown, "new", socket)

      assert result.assigns == socket.assigns
    end

    test "works when show_live_stream is false" do
      socket = build_socket(%{stream_content: "old", show_live_stream: false})

      {:noreply, result} = StreamState.handle_stream_replace(:text, "new", socket)

      assert result.assigns.stream_content == "new"
    end
  end

  describe "handle_stream_clear/1" do
    test "clears all stream content" do
      socket =
        build_socket(%{
          stream_content: "some content",
          stream_tool: "Bash",
          stream_thinking: "some thinking"
        })

      {:noreply, result} = StreamState.handle_stream_clear(socket)

      assert result.assigns.stream_content == ""
      assert result.assigns.stream_tool == nil
      assert result.assigns.stream_thinking == nil
    end

    test "handles clearing already-empty stream" do
      socket =
        build_socket(%{
          stream_content: "",
          stream_tool: nil,
          stream_thinking: nil
        })

      {:noreply, result} = StreamState.handle_stream_clear(socket)

      assert result.assigns.stream_content == ""
      assert result.assigns.stream_tool == nil
      assert result.assigns.stream_thinking == nil
    end

    test "clears partial state" do
      socket =
        build_socket(%{
          stream_content: "content here",
          stream_tool: nil,
          stream_thinking: "thinking here"
        })

      {:noreply, result} = StreamState.handle_stream_clear(socket)

      assert result.assigns.stream_content == ""
      assert result.assigns.stream_tool == nil
      assert result.assigns.stream_thinking == nil
    end
  end

  describe "handle_stream_tool_input/3" do
    test "sets stream_tool for command_execution with command" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} =
        StreamState.handle_stream_tool_input("command_execution", %{command: "ls -la"}, socket)

      assert result.assigns.stream_tool == "Bash: ls -la"
    end

    test "sets stream_tool for command_execution without command" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} =
        StreamState.handle_stream_tool_input("command_execution", %{}, socket)

      assert result.assigns.stream_tool == "Bash"
    end

    test "handles command field as atom key" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} =
        StreamState.handle_stream_tool_input(
          "command_execution",
          %{:command => "echo test"},
          socket
        )

      assert result.assigns.stream_tool == "Bash: echo test"
    end

    test "handles other tool types as base label" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} =
        StreamState.handle_stream_tool_input("web_search", %{query: "test"}, socket)

      assert result.assigns.stream_tool == "WebSearch"
    end

    test "handles mcp tool types" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} =
        StreamState.handle_stream_tool_input("mcp_tool_call", %{name: "test"}, socket)

      assert result.assigns.stream_tool == "MCP Tool"
    end

    test "handles empty command string" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} =
        StreamState.handle_stream_tool_input("command_execution", %{command: ""}, socket)

      assert result.assigns.stream_tool == "Bash"
    end

    test "handles nil command field" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} =
        StreamState.handle_stream_tool_input("command_execution", %{command: nil}, socket)

      assert result.assigns.stream_tool == "Bash"
    end
  end

  describe "handle_tool_use/2" do
    test "sets stream_tool from tool name" do
      socket = build_socket(%{stream_tool: nil})

      {:noreply, result} = StreamState.handle_tool_use("command_execution", socket)

      assert result.assigns.stream_tool == "Bash"
    end

    test "handles all known tool names" do
      tools = [
        {"command_execution", "Bash"},
        {"web_search", "WebSearch"},
        {"web_searches", "WebSearch"},
        {"mcp_tool_call", "MCP Tool"},
        {"mcp_tool_calls", "MCP Tool"},
        {"custom_tool", "custom_tool"}
      ]

      Enum.each(tools, fn {tool_name, expected_label} ->
        socket = build_socket(%{stream_tool: nil})
        {:noreply, result} = StreamState.handle_tool_use(tool_name, socket)
        assert result.assigns.stream_tool == expected_label
      end)
    end
  end

  describe "handle_queue_updated/2" do
    test "updates queued_prompts assign" do
      prompts = ["prompt1", "prompt2", "prompt3"]
      socket = build_socket(%{queued_prompts: []})

      {:noreply, result} = StreamState.handle_queue_updated(prompts, socket)

      assert result.assigns.queued_prompts == prompts
    end

    test "handles empty queue" do
      socket = build_socket(%{queued_prompts: ["old"]})

      {:noreply, result} = StreamState.handle_queue_updated([], socket)

      assert result.assigns.queued_prompts == []
    end

    test "handles queue with complex prompts" do
      prompts = [
        %{id: 1, text: "prompt 1"},
        %{id: 2, text: "prompt 2"}
      ]

      socket = build_socket(%{queued_prompts: []})

      {:noreply, result} = StreamState.handle_queue_updated(prompts, socket)

      assert result.assigns.queued_prompts == prompts
    end

    test "replaces previous queue entirely" do
      old_queue = ["old1", "old2"]
      new_queue = ["new1", "new2", "new3"]
      socket = build_socket(%{queued_prompts: old_queue})

      {:noreply, result} = StreamState.handle_queue_updated(new_queue, socket)

      assert result.assigns.queued_prompts == new_queue
      refute Enum.any?(result.assigns.queued_prompts, fn p -> p in old_queue end)
    end
  end

  describe "stream_tool_label/1 (via handle_stream_delta)" do
    test "maps all known tool names to labels" do
      test_cases = [
        {"command_execution", "Bash"},
        {"web_search", "WebSearch"},
        {"web_searches", "WebSearch"},
        {"mcp_tool_call", "MCP Tool"},
        {"mcp_tool_calls", "MCP Tool"},
        {"custom_name", "custom_name"}
      ]

      Enum.each(test_cases, fn {tool, expected} ->
        socket = build_socket(%{stream_tool: nil, show_live_stream: true})
        {:noreply, result} = StreamState.handle_stream_delta(:tool_use, tool, socket)
        assert result.assigns.stream_tool == expected, "Failed for tool: #{tool}"
      end)
    end
  end

  describe "integration scenarios" do
    test "stream text, then tool, then clear" do
      socket = build_socket(%{stream_content: "", stream_tool: nil, stream_thinking: nil})

      {:noreply, result1} = StreamState.handle_stream_delta(:text, "Processing...", socket)
      assert result1.assigns.stream_content == "Processing..."

      {:noreply, result2} =
        StreamState.handle_stream_delta(:tool_use, "command_execution", result1)

      assert result2.assigns.stream_tool == "Bash"

      {:noreply, result3} = StreamState.handle_stream_clear(result2)
      assert result3.assigns.stream_content == ""
      assert result3.assigns.stream_tool == nil
    end

    test "accumulate text and thinking separately" do
      socket =
        build_socket(%{
          stream_content: "",
          stream_thinking: "",
          show_live_stream: true
        })

      {:noreply, result1} = StreamState.handle_stream_delta(:text, "response", socket)
      assert result1.assigns.stream_content == "response"
      assert result1.assigns.stream_thinking == ""

      {:noreply, result2} = StreamState.handle_stream_replace(:thinking, "thinking", result1)
      assert result2.assigns.stream_content == "response"
      assert result2.assigns.stream_thinking == "thinking"
    end

    test "replace content while keeping thinking" do
      socket =
        build_socket(%{
          stream_content: "old response",
          stream_thinking: "thinking here",
          show_live_stream: true
        })

      {:noreply, result} = StreamState.handle_stream_replace(:text, "new response", socket)

      assert result.assigns.stream_content == "new response"
      assert result.assigns.stream_thinking == "thinking here"
    end
  end
end

defmodule EyeInTheSkyWeb.Live.Shared.DmStreamHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.DmStreamHelpers

  # DmStreamHelpers delegates to StreamState for most functions.
  # StreamState functions only call Phoenix.Component.assign/3, which works on
  # any map with :assigns. No DB or PubSub access needed for these tests.

  defp socket(assigns \\ %{}) do
    base = %{
      stream_content: "",
      stream_tool: nil,
      stream_thinking: nil,
      show_live_stream: false,
      queued_prompts: [],
      reload_timer: nil,
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  # ---------------------------------------------------------------------------
  # handle_stream_delta/3
  # ---------------------------------------------------------------------------

  describe "handle_stream_delta/3" do
    test "appends text to stream_content for :text type" do
      s = socket(%{stream_content: "hello "})
      {:noreply, result} = DmStreamHelpers.handle_stream_delta(:text, "world", s)
      assert result.assigns.stream_content == "hello world"
    end

    test "accumulates multiple text deltas" do
      s = socket(%{stream_content: ""})
      {:noreply, s1} = DmStreamHelpers.handle_stream_delta(:text, "foo", s)
      {:noreply, s2} = DmStreamHelpers.handle_stream_delta(:text, "bar", s1)
      assert s2.assigns.stream_content == "foobar"
    end

    test "sets stream_tool label for :tool_use type with known tool" do
      {:noreply, result} =
        DmStreamHelpers.handle_stream_delta(:tool_use, "command_execution", socket())

      assert result.assigns.stream_tool == "Bash"
    end

    test "sets stream_tool to tool name for :tool_use with unknown tool" do
      {:noreply, result} =
        DmStreamHelpers.handle_stream_delta(:tool_use, "my_custom_tool", socket())

      assert result.assigns.stream_tool == "my_custom_tool"
    end

    test "returns socket unchanged for :thinking type" do
      s = socket(%{stream_content: "existing"})
      {:noreply, result} = DmStreamHelpers.handle_stream_delta(:thinking, "thought", s)
      assert result.assigns.stream_content == "existing"
    end

    test "returns socket unchanged for unknown types" do
      s = socket()
      {:noreply, result} = DmStreamHelpers.handle_stream_delta(:unknown_type, "data", s)
      assert result == s
    end
  end

  # ---------------------------------------------------------------------------
  # handle_stream_replace/3
  # ---------------------------------------------------------------------------

  describe "handle_stream_replace/3" do
    test "replaces stream_content entirely for :text type" do
      s = socket(%{stream_content: "old content"})
      {:noreply, result} = DmStreamHelpers.handle_stream_replace(:text, "new content", s)
      assert result.assigns.stream_content == "new content"
    end

    test "replaces stream_thinking for :thinking type" do
      s = socket(%{stream_thinking: nil})
      {:noreply, result} = DmStreamHelpers.handle_stream_replace(:thinking, "some thought", s)
      assert result.assigns.stream_thinking == "some thought"
    end

    test "returns socket unchanged for unknown replace type" do
      s = socket()
      {:noreply, result} = DmStreamHelpers.handle_stream_replace(:other, "data", s)
      assert result == s
    end
  end

  # ---------------------------------------------------------------------------
  # handle_stream_clear/1
  # ---------------------------------------------------------------------------

  describe "handle_stream_clear/1" do
    test "clears stream_content to empty string" do
      s = socket(%{stream_content: "some text"})
      {:noreply, result} = DmStreamHelpers.handle_stream_clear(s)
      assert result.assigns.stream_content == ""
    end

    test "sets stream_tool to nil" do
      s = socket(%{stream_tool: "Bash"})
      {:noreply, result} = DmStreamHelpers.handle_stream_clear(s)
      assert result.assigns.stream_tool == nil
    end

    test "sets stream_thinking to nil" do
      s = socket(%{stream_thinking: "some thought"})
      {:noreply, result} = DmStreamHelpers.handle_stream_clear(s)
      assert result.assigns.stream_thinking == nil
    end

    test "clears all three stream assigns at once" do
      s = socket(%{stream_content: "text", stream_tool: "WebSearch", stream_thinking: "thought"})
      {:noreply, result} = DmStreamHelpers.handle_stream_clear(s)
      assert result.assigns.stream_content == ""
      assert result.assigns.stream_tool == nil
      assert result.assigns.stream_thinking == nil
    end
  end

  # ---------------------------------------------------------------------------
  # handle_stream_tool_input/3
  # ---------------------------------------------------------------------------

  describe "handle_stream_tool_input/3" do
    test "sets stream_tool label for known tool name" do
      {:noreply, result} =
        DmStreamHelpers.handle_stream_tool_input("command_execution", %{}, socket())

      assert result.assigns.stream_tool == "Bash"
    end

    test "appends command to label when command_execution has command key" do
      input = %{"command" => "ls -la"}

      {:noreply, result} =
        DmStreamHelpers.handle_stream_tool_input("command_execution", input, socket())

      assert result.assigns.stream_tool == "Bash: ls -la"
    end

    test "falls back to base label when command_execution has empty command" do
      input = %{"command" => ""}

      {:noreply, result} =
        DmStreamHelpers.handle_stream_tool_input("command_execution", input, socket())

      assert result.assigns.stream_tool == "Bash"
    end

    test "uses tool name as label for unknown tools" do
      {:noreply, result} = DmStreamHelpers.handle_stream_tool_input("my_tool", %{}, socket())
      assert result.assigns.stream_tool == "my_tool"
    end

    test "labels web_search correctly" do
      {:noreply, result} = DmStreamHelpers.handle_stream_tool_input("web_search", %{}, socket())
      assert result.assigns.stream_tool == "WebSearch"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_tool_use/2
  # ---------------------------------------------------------------------------

  describe "handle_tool_use/2" do
    test "assigns stream_tool label for known tool" do
      {:noreply, result} = DmStreamHelpers.handle_tool_use("web_search", socket())
      assert result.assigns.stream_tool == "WebSearch"
    end

    test "assigns stream_tool label for mcp_tool_call" do
      {:noreply, result} = DmStreamHelpers.handle_tool_use("mcp_tool_call", socket())
      assert result.assigns.stream_tool == "MCP Tool"
    end

    test "uses the raw tool name for unknown tools" do
      {:noreply, result} = DmStreamHelpers.handle_tool_use("some_custom_tool", socket())
      assert result.assigns.stream_tool == "some_custom_tool"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_tool_result/1
  # ---------------------------------------------------------------------------

  describe "handle_tool_result/1" do
    test "clears stream_tool assign" do
      # handle_tool_result calls Process.send_after(self(), ...) so self() must
      # be a real process. ExUnit test processes satisfy this requirement.
      s = socket(%{stream_tool: "Bash", reload_timer: nil})
      {:noreply, result} = DmStreamHelpers.handle_tool_result(s)
      assert result.assigns.stream_tool == nil
    end

    test "sets reload_timer to a non-nil timer reference" do
      s = socket(%{reload_timer: nil})
      {:noreply, result} = DmStreamHelpers.handle_tool_result(s)
      assert result.assigns.reload_timer != nil
    end

    test "cancels existing reload_timer before scheduling a new one" do
      # Schedule a timer, capture its ref, then call handle_tool_result.
      # The existing timer should be cancelled (no :do_message_reload arrives early).
      existing_timer = Process.send_after(self(), :do_message_reload, 10_000)
      s = socket(%{reload_timer: existing_timer})

      {:noreply, result} = DmStreamHelpers.handle_tool_result(s)
      # Existing timer was cancelled; new timer is different.
      assert result.assigns.reload_timer != existing_timer

      # Clean up the new timer to avoid noise in test mailbox.
      Process.cancel_timer(result.assigns.reload_timer)
      # Drain any leftover :do_message_reload in the mailbox.
      receive do
        :do_message_reload -> :ok
      after
        0 -> :ok
      end
    end

    test "sends :do_message_reload to self after the debounce period" do
      s = socket(%{reload_timer: nil})
      {:noreply, result} = DmStreamHelpers.handle_tool_result(s)
      # Default debounce is 300ms; wait a bit longer for the message.
      assert_receive :do_message_reload, 500
      # Cancel to avoid interference with other tests.
      Process.cancel_timer(result.assigns.reload_timer)
    end
  end

  # ---------------------------------------------------------------------------
  # handle_queue_updated/2
  # ---------------------------------------------------------------------------

  describe "handle_queue_updated/2" do
    test "assigns the provided prompts list" do
      prompts = ["prompt one", "prompt two"]
      {:noreply, result} = DmStreamHelpers.handle_queue_updated(prompts, socket())
      assert result.assigns.queued_prompts == prompts
    end

    test "assigns an empty list when called with []" do
      s = socket(%{queued_prompts: ["old"]})
      {:noreply, result} = DmStreamHelpers.handle_queue_updated([], s)
      assert result.assigns.queued_prompts == []
    end
  end
end

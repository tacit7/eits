defmodule EyeInTheSky.Codex.ParserTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Codex.Parser

  # ---------------------------------------------------------------------------
  # thread.started
  # ---------------------------------------------------------------------------

  describe "thread.started" do
    test "extracts thread_id as session_id" do
      line = Jason.encode!(%{"type" => "thread.started", "thread_id" => "abc-123"})
      assert {:session_id, "abc-123"} = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # turn.started
  # ---------------------------------------------------------------------------

  describe "turn.started" do
    test "returns :skip" do
      line = Jason.encode!(%{"type" => "turn.started"})
      assert :skip = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # item.started
  # ---------------------------------------------------------------------------

  describe "item.started" do
    test "command_execution emits partial tool_use" do
      line =
        Jason.encode!(%{
          "type" => "item.started",
          "item" => %{
            "type" => "command_execution",
            "command" => "ls -la",
            "working_directory" => "/tmp"
          }
        })

      assert {:ok, %Message{type: :tool_use, metadata: %{partial: true}} = msg} =
               Parser.parse_stream_line(line)

      assert msg.content.name == "command_execution"
      assert msg.content.input.command == "ls -la"
    end

    test "non-command item.started returns :skip" do
      line =
        Jason.encode!(%{
          "type" => "item.started",
          "item" => %{"type" => "agent_message"}
        })

      assert :skip = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - reasoning
  # ---------------------------------------------------------------------------

  describe "item.completed reasoning" do
    test "with text field returns thinking message" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "reasoning", "text" => "Let me think about this"}
        })

      assert {:ok, %Message{type: :thinking, content: "Let me think about this", delta: false}} =
               Parser.parse_stream_line(line)
    end

    test "with content array extracts text" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{
            "type" => "reasoning",
            "content" => [
              %{"type" => "text", "text" => "First thought. "},
              %{"type" => "text", "text" => "Second thought."}
            ]
          }
        })

      assert {:ok, %Message{type: :thinking, content: "First thought. Second thought."}} =
               Parser.parse_stream_line(line)
    end

    test "empty text returns :skip" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "reasoning", "text" => ""}
        })

      assert :skip = Parser.parse_stream_line(line)
    end

    test "empty content array returns :skip" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "reasoning", "content" => []}
        })

      assert :skip = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - agent_message
  # ---------------------------------------------------------------------------

  describe "item.completed agent_message" do
    test "with text field returns text message" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "agent_message", "text" => "Hello world"}
        })

      assert {:ok, %Message{type: :text, content: "Hello world", delta: false}} =
               Parser.parse_stream_line(line)
    end

    test "with content array extracts text" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{
            "type" => "agent_message",
            "content" => [
              %{"type" => "output_text", "text" => "Result: "},
              %{"type" => "text", "text" => "42"}
            ]
          }
        })

      assert {:ok, %Message{type: :text, content: "Result: 42"}} =
               Parser.parse_stream_line(line)
    end

    test "empty text returns :skip" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "agent_message", "text" => ""}
        })

      assert :skip = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - command_execution
  # ---------------------------------------------------------------------------

  describe "item.completed command_execution" do
    test "returns tool_use with command details (aggregated_output)" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{
            "type" => "command_execution",
            "command" => "/bin/zsh -lc 'echo hello'",
            "exit_code" => 0,
            "aggregated_output" => "hello\n",
            "status" => "completed"
          }
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.name == "command_execution"
      assert msg.content.input.command == "/bin/zsh -lc 'echo hello'"
      assert msg.content.input.exit_code == 0
      assert msg.content.input.output == "hello\n"
    end

    test "falls back to output field" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{
            "type" => "command_execution",
            "command" => "echo hi",
            "exit_code" => 0,
            "output" => "hi\n"
          }
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.input.output == "hi\n"
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - file_changes
  # ---------------------------------------------------------------------------

  describe "item.completed file_changes" do
    test "returns tool_use" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{
            "type" => "file_changes",
            "files" => [%{"path" => "foo.ex", "action" => "modified"}]
          }
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.name == "file_changes"
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - mcp_tool_calls
  # ---------------------------------------------------------------------------

  describe "item.completed mcp_tool_calls" do
    test "returns tool_use" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{
            "type" => "mcp_tool_calls",
            "tool" => "search",
            "args" => %{"query" => "test"}
          }
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.name == "mcp_tool_calls"
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - web_search / web_searches
  # ---------------------------------------------------------------------------

  describe "item.completed web_search" do
    test "web_search returns tool_use" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "web_search", "query" => "elixir genserver"}
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.name == "web_search"
    end

    test "web_searches returns tool_use" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "web_searches", "queries" => ["a", "b"]}
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.name == "web_searches"
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - plan_update / plan_updates
  # ---------------------------------------------------------------------------

  describe "item.completed plan_update" do
    test "plan_update returns tool_use" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "plan_update", "plan" => "Step 1: read code"}
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.name == "plan_update"
    end

    test "plan_updates returns tool_use" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "plan_updates", "steps" => ["a", "b"]}
        })

      assert {:ok, %Message{type: :tool_use} = msg} = Parser.parse_stream_line(line)
      assert msg.content.name == "plan_updates"
    end
  end

  # ---------------------------------------------------------------------------
  # item.completed - unknown type
  # ---------------------------------------------------------------------------

  describe "item.completed unknown" do
    test "returns :skip for unknown item type" do
      line =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "something_new", "data" => []}
        })

      assert :skip = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # turn.completed
  # ---------------------------------------------------------------------------

  describe "turn.completed" do
    test "returns result with usage stats" do
      line =
        Jason.encode!(%{
          "type" => "turn.completed",
          "thread_id" => "thread-456",
          "usage" => %{
            "input_tokens" => 100,
            "output_tokens" => 50,
            "total_tokens" => 150
          }
        })

      assert {:result, data} = Parser.parse_stream_line(line)
      assert data.input_tokens == 100
      assert data.output_tokens == 50
      assert data.total_tokens == 150
      assert data.session_id == "thread-456"
    end

    test "handles missing usage gracefully" do
      line = Jason.encode!(%{"type" => "turn.completed"})

      assert {:result, data} = Parser.parse_stream_line(line)
      assert data.input_tokens == 0
      assert data.output_tokens == 0
    end
  end

  # ---------------------------------------------------------------------------
  # turn.failed
  # ---------------------------------------------------------------------------

  describe "turn.failed" do
    test "returns error with message" do
      line = Jason.encode!(%{"type" => "turn.failed", "message" => "Rate limited"})
      assert {:error, {:turn_failed, "Rate limited"}} = Parser.parse_stream_line(line)
    end

    test "falls back to error field" do
      line = Jason.encode!(%{"type" => "turn.failed", "error" => "Timeout"})
      assert {:error, {:turn_failed, "Timeout"}} = Parser.parse_stream_line(line)
    end

    test "default message when none provided" do
      line = Jason.encode!(%{"type" => "turn.failed"})
      assert {:error, {:turn_failed, "Turn failed"}} = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # error
  # ---------------------------------------------------------------------------

  describe "error events" do
    test "type error with message" do
      line = Jason.encode!(%{"type" => "error", "message" => "Auth failed"})
      assert {:error, {:codex_error, "Auth failed"}} = Parser.parse_stream_line(line)
    end

    test "error object without type" do
      line = Jason.encode!(%{"error" => "Something broke"})
      assert {:error, {:codex_error, "Something broke"}} = Parser.parse_stream_line(line)
    end

    test "nested error object" do
      line = Jason.encode!(%{"error" => %{"message" => "Bad request"}})
      assert {:error, {:codex_error, "Bad request"}} = Parser.parse_stream_line(line)
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "empty line returns :skip" do
      assert :skip = Parser.parse_stream_line("")
    end

    test "whitespace-only line returns :skip" do
      assert :skip = Parser.parse_stream_line("   \n  ")
    end

    test "non-JSON line returns :skip (stderr/tracing)" do
      assert :skip = Parser.parse_stream_line("2026-02-16T10:00:00Z INFO some trace message")
    end

    test "unknown event type returns :skip" do
      line = Jason.encode!(%{"type" => "future.event", "data" => "whatever"})
      assert :skip = Parser.parse_stream_line(line)
    end

    test "malformed JSON returns :skip" do
      assert :skip = Parser.parse_stream_line("{broken json")
    end
  end
end

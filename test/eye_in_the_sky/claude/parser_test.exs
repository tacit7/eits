defmodule EyeInTheSky.Claude.ParserTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.Parser

  describe "parse_stream_line/1" do
    test "empty string returns :skip" do
      assert :skip = Parser.parse_stream_line("")
    end

    test "whitespace-only string returns :skip" do
      assert :skip = Parser.parse_stream_line("   \n  ")
    end

    test "plain text Error: line returns cli_error tuple" do
      line = "Error: Session ID 65bffb3e-aacf-41c6-8e15-2a8c9681163c is already in use."
      assert {:error, {:cli_error, ^line}} = Parser.parse_stream_line(line)
    end

    test "Error: with different messages returns cli_error" do
      assert {:error, {:cli_error, "Error: Credit balance is too low"}} =
               Parser.parse_stream_line("Error: Credit balance is too low")
    end

    test "non-JSON non-error text returns :skip instead of crashing" do
      assert :skip = Parser.parse_stream_line("some random plain text output")
    end

    test "init event returns session_id tuple" do
      line = Jason.encode!(%{"type" => "init", "session_id" => "abc-123"})
      assert {:session_id, "abc-123"} = Parser.parse_stream_line(line)
    end

    test "system init event returns session_id tuple" do
      line =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "abc-123"
        })

      assert {:session_id, "abc-123"} = Parser.parse_stream_line(line)
    end

    test "system event without subtype returns :skip" do
      line = Jason.encode!(%{"type" => "system", "subtype" => "something_else"})
      assert :skip = Parser.parse_stream_line(line)
    end

    test "assistant message with text returns ok message" do
      line =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{
            "content" => [%{"type" => "text", "text" => "Hello world"}]
          }
        })

      assert {:ok, msg} = Parser.parse_stream_line(line)
      assert msg.type == :text
      assert msg.content == "Hello world"
    end

    test "assistant message with tool use returns ok message" do
      line =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{
            "content" => [%{"type" => "tool_use", "name" => "Read", "id" => "t1", "input" => %{}}]
          }
        })

      assert {:ok, msg} = Parser.parse_stream_line(line)
      assert msg.type == :tool_use
    end

    test "assistant message with empty content returns :skip" do
      line =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{"content" => []}
        })

      assert :skip = Parser.parse_stream_line(line)
    end

    test "result event returns result tuple" do
      line =
        Jason.encode!(%{
          "type" => "result",
          "session_id" => "abc-123",
          "result" => "task done",
          "uuid" => "xyz",
          "duration_ms" => 1500,
          "total_cost_usd" => 0.001,
          "num_turns" => 3,
          "is_error" => false
        })

      assert {:result, data} = Parser.parse_stream_line(line)
      assert data.session_id == "abc-123"
      assert data.result == "task done"
      assert data.duration_ms == 1500
      assert data.is_error == false
    end

    test "error event returns error tuple" do
      line =
        Jason.encode!(%{
          "type" => "error",
          "error" => %{"type" => "api_error", "message" => "Rate limit exceeded"}
        })

      assert {:error, {:api_error, "Rate limit exceeded"}} = Parser.parse_stream_line(line)
    end

    test "unknown event type returns :skip" do
      line = Jason.encode!(%{"type" => "unknown_future_event", "data" => "stuff"})
      assert :skip = Parser.parse_stream_line(line)
    end

    test "text delta stream event returns ok message" do
      line =
        Jason.encode!(%{
          "type" => "stream_event",
          "event" => %{
            "type" => "content_block_delta",
            "delta" => %{"type" => "text_delta", "text" => "partial "}
          }
        })

      assert {:ok, msg} = Parser.parse_stream_line(line)
      assert msg.type == :text
      assert msg.delta == true
      assert msg.content == "partial "
    end
  end
end

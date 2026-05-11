defmodule EyeInTheSky.Metrics.TokenParserTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Metrics.TokenParser

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Writes lines to a temp file and returns the path. Caller owns cleanup via
  # on_exit or the tmpdir approach below.
  defp write_jsonl(lines) do
    path =
      System.tmp_dir!()
      |> Path.join("token_parser_test_#{System.unique_integer([:positive])}.jsonl")

    File.write!(path, Enum.join(lines, "\n"))
    path
  end

  defp assistant_entry(request_id, model, input, output, cache_creation \\ 0, cache_read \\ 0) do
    Jason.encode!(%{
      "type" => "assistant",
      "requestId" => request_id,
      "message" => %{
        "model" => model,
        "usage" => %{
          "input_tokens" => input,
          "output_tokens" => output,
          "cache_creation_input_tokens" => cache_creation,
          "cache_read_input_tokens" => cache_read
        }
      }
    })
  end

  defp user_entry(text) do
    Jason.encode!(%{"type" => "user", "message" => %{"content" => text}})
  end

  defp system_entry do
    Jason.encode!(%{"type" => "system", "subtype" => "init"})
  end

  # ---------------------------------------------------------------------------
  # empty_usage/0
  # ---------------------------------------------------------------------------

  describe "empty_usage/0" do
    test "returns zero-valued map with expected keys" do
      usage = TokenParser.empty_usage()

      assert usage == %{
               input_tokens: 0,
               output_tokens: 0,
               cache_creation_input_tokens: 0,
               cache_read_input_tokens: 0,
               total_tokens: 0,
               request_count: 0,
               subagent_count: 0,
               models: %{}
             }
    end
  end

  # ---------------------------------------------------------------------------
  # parse_file/1 — error paths
  # ---------------------------------------------------------------------------

  describe "parse_file/1 error paths" do
    test "returns {:error, :not_found} for a missing file" do
      assert {:error, :not_found} = TokenParser.parse_file("/nonexistent/path/session.jsonl")
    end

    test "returns {:ok, empty_usage} for an empty JSONL file" do
      path = write_jsonl([])
      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage == TokenParser.empty_usage()
    end
  end

  # ---------------------------------------------------------------------------
  # parse_file/1 — happy paths
  # ---------------------------------------------------------------------------

  describe "parse_file/1 token accumulation" do
    test "sums input and output tokens from a single assistant entry" do
      path = write_jsonl([assistant_entry("req-1", "claude-3-5-sonnet", 100, 50)])
      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)

      assert usage.input_tokens == 100
      assert usage.output_tokens == 50
      assert usage.total_tokens == 150
      assert usage.request_count == 1
    end

    test "accumulates tokens across multiple distinct requests" do
      path =
        write_jsonl([
          assistant_entry("req-1", "claude-3-5-sonnet", 100, 50),
          assistant_entry("req-2", "claude-3-5-sonnet", 200, 75)
        ])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)

      assert usage.input_tokens == 300
      assert usage.output_tokens == 125
      assert usage.total_tokens == 425
      assert usage.request_count == 2
    end

    test "includes cache tokens in total_tokens" do
      path =
        write_jsonl([
          assistant_entry("req-1", "claude-3-5-sonnet", 50, 20, 1000, 500)
        ])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)

      assert usage.cache_creation_input_tokens == 1000
      assert usage.cache_read_input_tokens == 500
      assert usage.total_tokens == 50 + 20 + 1000 + 500
    end

    test "tracks model request counts in the models map" do
      path =
        write_jsonl([
          assistant_entry("req-1", "claude-3-5-sonnet", 10, 5),
          assistant_entry("req-2", "claude-3-5-haiku", 20, 8),
          assistant_entry("req-3", "claude-3-5-sonnet", 15, 6)
        ])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)

      assert usage.models["claude-3-5-sonnet"] == 2
      assert usage.models["claude-3-5-haiku"] == 1
    end

    test "falls back to 'unknown' model when model key is absent" do
      line =
        Jason.encode!(%{
          "type" => "assistant",
          "requestId" => "req-no-model",
          "message" => %{
            "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
          }
        })

      path = write_jsonl([line])
      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.models["unknown"] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # parse_file/1 — deduplication
  # ---------------------------------------------------------------------------

  describe "parse_file/1 deduplication" do
    test "deduplicates streaming chunks with the same requestId" do
      # Streaming sends multiple chunks per request; each has the SAME usage.
      # Only one should be counted.
      path =
        write_jsonl([
          assistant_entry("req-stream", "claude-3-5-sonnet", 100, 50),
          assistant_entry("req-stream", "claude-3-5-sonnet", 100, 50),
          assistant_entry("req-stream", "claude-3-5-sonnet", 100, 50)
        ])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)

      assert usage.request_count == 1
      assert usage.input_tokens == 100
      assert usage.output_tokens == 50
    end

    test "does not deduplicate entries with distinct requestIds" do
      path =
        write_jsonl([
          assistant_entry("req-1", "claude-3-5-sonnet", 100, 50),
          assistant_entry("req-2", "claude-3-5-sonnet", 200, 75)
        ])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.request_count == 2
    end

    test "treats entries with no requestId as distinct (no cross-collapse)" do
      # Entries without requestId get a unique make_ref() key, so they each count.
      line_without_id =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{
            "model" => "claude-3-5-sonnet",
            "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
          }
        })

      path = write_jsonl([line_without_id, line_without_id])
      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.request_count == 2
    end
  end

  # ---------------------------------------------------------------------------
  # parse_file/1 — filtering
  # ---------------------------------------------------------------------------

  describe "parse_file/1 filtering" do
    test "ignores user messages" do
      path =
        write_jsonl([user_entry("hello"), assistant_entry("req-1", "claude-3-5-sonnet", 10, 5)])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.request_count == 1
    end

    test "ignores system messages" do
      path = write_jsonl([system_entry(), assistant_entry("req-1", "claude-3-5-sonnet", 10, 5)])
      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.request_count == 1
    end

    test "ignores assistant entries that lack a usage block" do
      line =
        Jason.encode!(%{
          "type" => "assistant",
          "requestId" => "req-no-usage",
          "message" => %{"content" => "hi"}
        })

      path = write_jsonl([line])
      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.request_count == 0
      assert usage.input_tokens == 0
    end

    test "handles malformed JSON lines gracefully without crashing" do
      path =
        write_jsonl([
          "this is not json",
          assistant_entry("req-1", "claude-3-5-sonnet", 10, 5),
          "{broken json",
          assistant_entry("req-2", "claude-3-5-sonnet", 20, 8)
        ])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.request_count == 2
      assert usage.input_tokens == 30
    end

    test "handles blank lines without crashing" do
      path =
        write_jsonl([
          "",
          assistant_entry("req-1", "claude-3-5-sonnet", 10, 5),
          "   "
        ])

      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_file(path)
      assert usage.request_count == 1
    end
  end

  # ---------------------------------------------------------------------------
  # parse_session/1
  # ---------------------------------------------------------------------------

  describe "parse_session/1" do
    test "returns main file usage when no subagent directory exists" do
      path = write_jsonl([assistant_entry("req-1", "claude-3-5-sonnet", 100, 50)])
      on_exit(fn -> File.rm(path) end)

      assert {:ok, usage} = TokenParser.parse_session(path)

      assert usage.input_tokens == 100
      assert usage.output_tokens == 50
      assert usage.request_count == 1
      assert usage.subagent_count == 0
    end

    test "propagates error when main file does not exist" do
      assert {:error, :not_found} = TokenParser.parse_session("/no/such/file.jsonl")
    end

    test "combines main and subagent token counts" do
      tmpdir = System.tmp_dir!()
      session_name = "session_#{System.unique_integer([:positive])}"
      main_path = Path.join(tmpdir, "#{session_name}.jsonl")
      subagent_dir = Path.join(tmpdir, "#{session_name}/subagents")

      File.mkdir_p!(subagent_dir)

      File.write!(main_path, assistant_entry("main-req", "claude-3-5-sonnet", 200, 100))

      File.write!(
        Path.join(subagent_dir, "agent-1.jsonl"),
        assistant_entry("sub1-req", "claude-3-5-haiku", 50, 20)
      )

      File.write!(
        Path.join(subagent_dir, "agent-2.jsonl"),
        assistant_entry("sub2-req", "claude-3-5-haiku", 30, 10)
      )

      on_exit(fn ->
        File.rm(main_path)
        File.rm_rf(Path.join(tmpdir, session_name))
      end)

      assert {:ok, usage} = TokenParser.parse_session(main_path)

      assert usage.input_tokens == 200 + 50 + 30
      assert usage.output_tokens == 100 + 20 + 10
      assert usage.total_tokens == 280 + 130
      assert usage.request_count == 3
      assert usage.subagent_count == 2
    end

    test "counts only .jsonl files in subagent directory" do
      tmpdir = System.tmp_dir!()
      session_name = "session_#{System.unique_integer([:positive])}"
      main_path = Path.join(tmpdir, "#{session_name}.jsonl")
      subagent_dir = Path.join(tmpdir, "#{session_name}/subagents")

      File.mkdir_p!(subagent_dir)
      File.write!(main_path, assistant_entry("main-req", "claude-3-5-sonnet", 100, 50))

      File.write!(
        Path.join(subagent_dir, "agent-1.jsonl"),
        assistant_entry("sub-req", "claude-3-5-sonnet", 10, 5)
      )

      File.write!(Path.join(subagent_dir, "README.txt"), "not a jsonl file")
      File.write!(Path.join(subagent_dir, "metadata.json"), "{}")

      on_exit(fn ->
        File.rm(main_path)
        File.rm_rf(Path.join(tmpdir, session_name))
      end)

      assert {:ok, usage} = TokenParser.parse_session(main_path)

      # Only one subagent .jsonl file should count
      assert usage.subagent_count == 1
      assert usage.request_count == 2
    end

    test "handles subagent file that contains malformed JSON gracefully" do
      tmpdir = System.tmp_dir!()
      session_name = "session_#{System.unique_integer([:positive])}"
      main_path = Path.join(tmpdir, "#{session_name}.jsonl")
      subagent_dir = Path.join(tmpdir, "#{session_name}/subagents")

      File.mkdir_p!(subagent_dir)
      File.write!(main_path, assistant_entry("main-req", "claude-3-5-sonnet", 100, 50))
      File.write!(Path.join(subagent_dir, "agent-bad.jsonl"), "not json at all")

      on_exit(fn ->
        File.rm(main_path)
        File.rm_rf(Path.join(tmpdir, session_name))
      end)

      assert {:ok, usage} = TokenParser.parse_session(main_path)

      # Main file parsed; bad subagent contributes 0 tokens but is still counted
      assert usage.subagent_count == 1
      assert usage.input_tokens == 100
    end

    test "merges model counts across main and subagent files" do
      tmpdir = System.tmp_dir!()
      session_name = "session_#{System.unique_integer([:positive])}"
      main_path = Path.join(tmpdir, "#{session_name}.jsonl")
      subagent_dir = Path.join(tmpdir, "#{session_name}/subagents")

      File.mkdir_p!(subagent_dir)

      File.write!(
        main_path,
        [
          assistant_entry("req-m1", "claude-3-5-sonnet", 10, 5),
          assistant_entry("req-m2", "claude-3-5-sonnet", 10, 5)
        ]
        |> Enum.join("\n")
      )

      File.write!(
        Path.join(subagent_dir, "agent-1.jsonl"),
        assistant_entry("req-s1", "claude-3-5-sonnet", 10, 5)
      )

      on_exit(fn ->
        File.rm(main_path)
        File.rm_rf(Path.join(tmpdir, session_name))
      end)

      assert {:ok, usage} = TokenParser.parse_session(main_path)
      assert usage.models["claude-3-5-sonnet"] == 3
    end
  end
end

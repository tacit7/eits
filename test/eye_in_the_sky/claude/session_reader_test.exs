defmodule EyeInTheSky.Claude.SessionReaderTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.SessionReader

  @fixtures_dir Path.join([__DIR__, "..", "..", "fixtures"])

  describe "escape_project_path/1" do
    test "replaces slashes with hyphens" do
      assert SessionReader.escape_project_path("/Users/user/projects/myapp") ==
               "-Users-user-projects-myapp"
    end

    test "handles root path" do
      assert SessionReader.escape_project_path("/") == "-"
    end

    test "handles path without leading slash" do
      assert SessionReader.escape_project_path("relative/path") == "relative-path"
    end
  end

  describe "parse_session_file/2" do
    test "parses JSONL file and returns conversation messages" do
      file_path = Path.join(@fixtures_dir, "claude_session_messages.jsonl")
      {:ok, messages} = SessionReader.parse_session_file(file_path, 100)

      # Should include user and assistant messages, not system messages
      types = Enum.map(messages, & &1["type"])
      assert "user" in types
      assert "assistant" in types
      refute "system" in types
    end

    test "respects limit parameter returning last N messages" do
      file_path = Path.join(@fixtures_dir, "claude_session_messages.jsonl")
      {:ok, all_messages} = SessionReader.parse_session_file(file_path, 100)
      {:ok, limited} = SessionReader.parse_session_file(file_path, 2)

      assert length(limited) == 2
      # Should be the LAST 2 messages
      assert limited == Enum.take(all_messages, -2)
    end

    test "returns error for non-existent file" do
      {:error, :enoent} = SessionReader.parse_session_file("/tmp/nonexistent.jsonl", 10)
    end

    test "handles file with only system messages" do
      # Write a temp file with only system messages
      path = Path.join(System.tmp_dir!(), "test_system_only.jsonl")

      File.write!(path, """
      {"type":"system","subtype":"init","session_id":"abc"}
      {"type":"system","subtype":"something","data":"test"}
      """)

      {:ok, messages} = SessionReader.parse_session_file(path, 10)
      assert messages == []

      File.rm!(path)
    end

    test "skips malformed JSON lines gracefully" do
      path = Path.join(System.tmp_dir!(), "test_malformed.jsonl")

      File.write!(path, """
      {"type":"user","uuid":"u1","message":{"role":"user","content":"hello"}}
      this is not valid json
      {"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}
      """)

      {:ok, messages} = SessionReader.parse_session_file(path, 10)
      assert length(messages) == 2

      File.rm!(path)
    end
  end

  describe "format_messages/1" do
    test "extracts role and text content from messages" do
      messages = [
        %{
          "type" => "user",
          "uuid" => "u1",
          "message" => %{"role" => "user", "content" => "Hello"},
          "timestamp" => "2026-03-01T10:00:00Z"
        },
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => "Hi there"}]
          },
          "timestamp" => "2026-03-01T10:00:01Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      assert length(formatted) == 2

      [user_msg, asst_msg] = formatted
      assert user_msg.role == "user"
      assert user_msg.content == "Hello"
      assert user_msg.uuid == "u1"

      assert asst_msg.role == "assistant"
      assert asst_msg.content == "Hi there"
    end

    test "formats tool_use content with compact summaries" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Read",
                "input" => %{"file_path" => "/tmp/test.txt"}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      assert length(formatted) == 1
      assert hd(formatted).content =~ "`Read`"
      assert hd(formatted).content =~ "/tmp/test.txt"
    end

    test "filters out messages with empty content" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{"role" => "assistant", "content" => []},
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      assert formatted == []
    end

    test "filters out messages starting with <" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => "<system>internal</system>"}]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      assert formatted == []
    end

    test "generates timestamp when missing" do
      messages = [
        %{
          "type" => "user",
          "uuid" => "u1",
          "message" => %{"role" => "user", "content" => "No timestamp"}
        }
      ]

      formatted = SessionReader.format_messages(messages)
      assert length(formatted) == 1
      assert formatted |> hd() |> Map.get(:timestamp) |> is_binary()
    end

    test "handles mixed text and tool_use content" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{"type" => "text", "text" => "Let me read that file."},
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Read",
                "input" => %{"file_path" => "/tmp/f.txt"}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      assert length(formatted) == 1
      content = hd(formatted).content
      assert content =~ "Let me read that file."
      assert content =~ "`Read`"
    end
  end

  describe "read_tool_events/2 with fixture" do
    test "extracts tool events from session file" do
      # Create a temp session file with tool use
      session_id = "test-tool-events-#{System.unique_integer([:positive])}"
      home = System.get_env("HOME")
      project_path = "/tmp/test-project"
      escaped = SessionReader.escape_project_path(project_path)
      dir = Path.join([home, ".claude", "projects", escaped])
      file_path = Path.join(dir, "#{session_id}.jsonl")

      File.mkdir_p!(dir)

      content =
        Enum.join(
          [
            Jason.encode!(%{
              "type" => "assistant",
              "message" => %{
                "content" => [
                  %{
                    "type" => "tool_use",
                    "id" => "t1",
                    "name" => "Read",
                    "input" => %{"file_path" => "/tmp/a.txt"}
                  },
                  %{
                    "type" => "tool_use",
                    "id" => "t2",
                    "name" => "Bash",
                    "input" => %{"command" => "ls -la"}
                  }
                ]
              },
              "timestamp" => "2026-03-01T10:00:00Z"
            }),
            Jason.encode!(%{
              "type" => "user",
              "message" => %{"content" => "next step"}
            }),
            Jason.encode!(%{
              "type" => "assistant",
              "message" => %{
                "content" => [
                  %{"type" => "text", "text" => "Done."}
                ]
              }
            }),
            Jason.encode!(%{
              "type" => "assistant",
              "message" => %{
                "content" => [
                  %{
                    "type" => "tool_use",
                    "id" => "t3",
                    "name" => "Write",
                    "input" => %{"file_path" => "/tmp/b.txt"}
                  }
                ]
              },
              "timestamp" => "2026-03-01T10:00:05Z"
            })
          ],
          "\n"
        )

      File.write!(file_path, content)

      {:ok, events} = SessionReader.read_tool_events(session_id, project_path)

      assert length(events) == 3

      [e1, e2, e3] = events
      assert e1.type == "Read"
      assert e1.id == "t1"
      assert e1.message =~ "`Read`"

      assert e2.type == "Bash"
      assert e2.id == "t2"
      assert e2.message =~ "`Bash`"
      assert e2.timestamp == "2026-03-01T10:00:00Z"

      assert e3.type == "Write"
      assert e3.id == "t3"
      assert e3.message =~ "`Write`"
      assert e3.timestamp == "2026-03-01T10:00:05Z"

      # Cleanup
      File.rm!(file_path)
    end

    test "returns error when session file not found" do
      assert {:error, :not_found} =
               SessionReader.read_tool_events("nonexistent-session", "/tmp/nonexistent-project")
    end
  end

  describe "discover_all_sessions/0 escaped_path regression" do
    test "escaped_path preserves exact directory name for hyphenated paths" do
      # Simulate a project with hyphens: /tmp/my-cool-app
      # Escaped dir name: -tmp-my-cool-app
      home = System.get_env("HOME")
      escaped_name = "-tmp-my-cool-app"
      project_dir = Path.join([home, ".claude", "projects", escaped_name])
      session_id = "test-escaped-#{System.unique_integer([:positive])}"
      file_path = Path.join(project_dir, "#{session_id}.jsonl")

      File.mkdir_p!(project_dir)
      File.write!(file_path, ~s|{"type":"user","message":{"content":"hi"}}\n|)

      sessions = SessionReader.discover_all_sessions()
      session = Enum.find(sessions, fn s -> s.session_id == session_id end)

      assert session != nil
      # escaped_path must be the raw directory name — no transformation
      assert session.escaped_path == escaped_name

      # project_path is lossy: it turns ALL hyphens into slashes,
      # so /tmp/my-cool-app becomes /tmp/my/cool/app (wrong but documented)
      assert session.project_path == "/tmp/my/cool/app"

      # Cleanup
      File.rm!(file_path)
      File.rmdir(project_dir)
    end
  end

  describe "read_usage/2" do
    defp write_usage_session(session_id, project_path, lines) do
      home = System.get_env("HOME")
      escaped = SessionReader.escape_project_path(project_path)
      dir = Path.join([home, ".claude", "projects", escaped])
      file_path = Path.join(dir, "#{session_id}.jsonl")
      File.mkdir_p!(dir)
      File.write!(file_path, Enum.join(lines, "\n") <> "\n")
      file_path
    end

    test "happy path: sums tokens from assistant entry and cost from result entry" do
      session_id = "test-usage-happy-#{System.unique_integer([:positive])}"
      project_path = "/tmp/test-usage-project"

      file_path =
        write_usage_session(session_id, project_path, [
          Jason.encode!(%{
            "type" => "assistant",
            "message" => %{
              "role" => "assistant",
              "content" => [%{"type" => "text", "text" => "hello"}],
              "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
            }
          }),
          Jason.encode!(%{
            "type" => "result",
            "total_cost_usd" => 0.002
          })
        ])

      assert {:ok, 15, 0.002} = SessionReader.read_usage(session_id, project_path)

      File.rm!(file_path)
    end

    test "irrelevant lines only: returns zero tokens and zero cost" do
      session_id = "test-usage-irrelevant-#{System.unique_integer([:positive])}"
      project_path = "/tmp/test-usage-project"

      file_path =
        write_usage_session(session_id, project_path, [
          Jason.encode!(%{
            "type" => "user",
            "message" => %{"role" => "user", "content" => "hi"}
          }),
          Jason.encode!(%{
            "type" => "assistant",
            "message" => %{
              "role" => "assistant",
              "content" => [
                %{"type" => "tool_use", "id" => "t1", "name" => "Read", "input" => %{}}
              ]
            }
          }),
          "this is garbage"
        ])

      assert {:ok, tokens, cost} = SessionReader.read_usage(session_id, project_path)
      assert tokens == 0
      assert cost == +0.0

      File.rm!(file_path)
    end

    test "mixed: only valid assistant/result lines are summed" do
      session_id = "test-usage-mixed-#{System.unique_integer([:positive])}"
      project_path = "/tmp/test-usage-project"

      file_path =
        write_usage_session(session_id, project_path, [
          Jason.encode!(%{
            "type" => "user",
            "message" => %{"role" => "user", "content" => "go"}
          }),
          Jason.encode!(%{
            "type" => "assistant",
            "message" => %{
              "role" => "assistant",
              "content" => [%{"type" => "text", "text" => "step 1"}],
              "usage" => %{"input_tokens" => 20, "output_tokens" => 8}
            }
          }),
          Jason.encode!(%{
            "type" => "assistant",
            "message" => %{
              "role" => "assistant",
              "content" => [%{"type" => "text", "text" => "step 2"}],
              "usage" => %{"input_tokens" => 5, "output_tokens" => 3}
            }
          }),
          Jason.encode!(%{
            "type" => "result",
            "total_cost_usd" => 0.001
          }),
          Jason.encode!(%{
            "type" => "result",
            "total_cost_usd" => 0.003
          }),
          "bad json line"
        ])

      assert {:ok, 36, cost} = SessionReader.read_usage(session_id, project_path)
      assert_in_delta cost, 0.004, 1.0e-9

      File.rm!(file_path)
    end
  end

  describe "find_session_file/2" do
    test "returns {:ok, path} when file exists" do
      session_id = "test-find-#{System.unique_integer([:positive])}"
      home = System.get_env("HOME")
      project_path = "/tmp/test-find-project"
      escaped = SessionReader.escape_project_path(project_path)
      dir = Path.join([home, ".claude", "projects", escaped])
      file_path = Path.join(dir, "#{session_id}.jsonl")

      File.mkdir_p!(dir)
      File.write!(file_path, "{}\n")

      assert {:ok, ^file_path} = SessionReader.find_session_file(session_id, project_path)

      File.rm!(file_path)
    end

    test "returns {:error, :not_found} when file does not exist" do
      assert {:error, :not_found} =
               SessionReader.find_session_file("no-such-id", "/tmp/no-such-project")
    end
  end

  describe "tool call formatting via format_messages" do
    test "formats Grep with pattern and path" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Grep",
                "input" => %{"pattern" => "defmodule", "path" => "/tmp/lib"}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      content = hd(formatted).content
      assert content =~ "`Grep`"
      assert content =~ "defmodule"
      assert content =~ "/tmp/lib"
    end

    test "formats Glob with pattern" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Glob",
                "input" => %{"pattern" => "**/*.ex"}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      content = hd(formatted).content
      assert content =~ "`Glob`"
      assert content =~ "**/*.ex"
    end

    test "formats Bash without truncation for long commands" do
      long_cmd = String.duplicate("a", 200)

      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Bash",
                "input" => %{"command" => long_cmd}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      content = hd(formatted).content
      assert content =~ "`Bash`"
      assert content =~ long_cmd
    end

    test "formats Task with truncation" do
      long_prompt = String.duplicate("x", 200)

      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Task",
                "input" => %{"prompt" => long_prompt}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      content = hd(formatted).content
      assert content =~ "`Task`"
      assert content =~ "..."
    end

    test "formats unknown tool with key-value summary" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "CustomTool",
                "input" => %{"key1" => "value1", "key2" => "value2"}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      content = hd(formatted).content
      assert content =~ "`CustomTool`"
    end

    test "formats Edit with file_path" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Edit",
                "input" => %{"file_path" => "/tmp/edited.ex"}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      content = hd(formatted).content
      assert content =~ "`Edit`"
      assert content =~ "/tmp/edited.ex"
    end

    test "formats Write with file_path" do
      messages = [
        %{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "t1",
                "name" => "Write",
                "input" => %{"file_path" => "/tmp/new_file.ex"}
              }
            ]
          },
          "timestamp" => "2026-03-01T10:00:00Z"
        }
      ]

      formatted = SessionReader.format_messages(messages)
      content = hd(formatted).content
      assert content =~ "`Write`"
      assert content =~ "/tmp/new_file.ex"
    end
  end
end

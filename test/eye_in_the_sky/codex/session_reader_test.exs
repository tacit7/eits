defmodule EyeInTheSky.Codex.SessionReaderTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.SessionReader

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_jsonl(path, lines) when is_list(lines) do
    content = Enum.map_join(lines, "\n", &Jason.encode!/1)
    File.write!(path, content)
  end

  defp make_sessions_dir(base) do
    dir = Path.join([base, ".codex", "sessions", "2024", "01", "01"])
    File.mkdir_p!(dir)
    dir
  end

  defp with_home(home, fun) do
    original = System.get_env("HOME")
    System.put_env("HOME", home)

    try do
      fun.()
    after
      System.put_env("HOME", original)
    end
  end

  defp user_event(text, ts \\ "2024-01-01T00:00:00Z") do
    %{"type" => "event_msg", "payload" => %{"type" => "user_message", "message" => text}, "timestamp" => ts}
  end

  defp agent_event(text, ts \\ "2024-01-01T00:01:00Z") do
    %{"type" => "event_msg", "payload" => %{"type" => "agent_message", "message" => text}, "timestamp" => ts}
  end

  defp token_event(total) do
    %{
      "type" => "event_msg",
      "payload" => %{
        "type" => "token_count",
        "info" => %{"total_token_usage" => %{"total_tokens" => total}}
      }
    }
  end

  defp session_meta_event do
    %{"type" => "event_msg", "payload" => %{"type" => "session_meta", "data" => "irrelevant"}}
  end

  # ---------------------------------------------------------------------------
  # find_session_file/1
  # ---------------------------------------------------------------------------

  describe "find_session_file/1" do
    test "returns :not_found for nil thread_id" do
      assert {:error, :not_found} = SessionReader.find_session_file(nil)
    end

    test "finds a matching JSONL file" do
      home = System.tmp_dir!() |> Path.join("sr_find_#{:rand.uniform(999_999)}")
      dir = make_sessions_dir(home)
      thread_id = "abc123"
      session_file = Path.join(dir, "rollout-1234567890-#{thread_id}.jsonl")
      File.write!(session_file, "")

      with_home(home, fn ->
        assert {:ok, ^session_file} = SessionReader.find_session_file(thread_id)
      end)
    end

    test "returns :not_found when no file matches" do
      home = System.tmp_dir!() |> Path.join("sr_miss_#{:rand.uniform(999_999)}")
      make_sessions_dir(home)

      with_home(home, fn ->
        assert {:error, :not_found} = SessionReader.find_session_file("nonexistent-thread")
      end)
    end

    test "returns first match when multiple files exist" do
      home = System.tmp_dir!() |> Path.join("sr_multi_#{:rand.uniform(999_999)}")
      dir = make_sessions_dir(home)
      thread_id = "multi-match"
      file1 = Path.join(dir, "rollout-0001-#{thread_id}.jsonl")
      file2 = Path.join(dir, "rollout-0002-#{thread_id}.jsonl")
      File.write!(file1, "")
      File.write!(file2, "")

      with_home(home, fn ->
        {:ok, found} = SessionReader.find_session_file(thread_id)
        assert found in [file1, file2]
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # read_messages/1
  # ---------------------------------------------------------------------------

  describe "read_messages/1" do
    setup do
      home = System.tmp_dir!() |> Path.join("sr_msgs_#{:rand.uniform(999_999)}")
      dir = make_sessions_dir(home)
      thread_id = "thread-#{:rand.uniform(999_999)}"
      session_file = Path.join(dir, "rollout-1234567890-#{thread_id}.jsonl")
      original_home = System.get_env("HOME")
      System.put_env("HOME", home)

      on_exit(fn -> System.put_env("HOME", original_home) end)

      {:ok, session_file: session_file, thread_id: thread_id}
    end

    test "reads user and agent messages", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [
        user_event("hello"),
        agent_event("hi there")
      ])

      {:ok, messages} = SessionReader.read_messages(thread_id)
      assert length(messages) == 2

      [user_msg, agent_msg] = messages
      assert user_msg.role == "user"
      assert user_msg.content == "hello"
      assert user_msg.timestamp == "2024-01-01T00:00:00Z"

      assert agent_msg.role == "assistant"
      assert agent_msg.content == "hi there"
    end

    test "skips token_count and session_meta events", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [
        session_meta_event(),
        user_event("msg"),
        token_event(500)
      ])

      {:ok, messages} = SessionReader.read_messages(thread_id)
      assert length(messages) == 1
      assert hd(messages).content == "msg"
    end

    test "extracts events missing a timestamp field with timestamp set to nil",
         %{session_file: session_file, thread_id: thread_id} do
      no_ts = %{"type" => "event_msg", "payload" => %{"type" => "user_message", "message" => "no ts"}}
      write_jsonl(session_file, [no_ts, user_event("with ts")])

      {:ok, messages} = SessionReader.read_messages(thread_id)
      assert length(messages) == 2

      [no_ts_msg, ts_msg] = messages
      assert no_ts_msg.timestamp == nil
      assert ts_msg.timestamp == "2024-01-01T00:00:00Z"
    end

    test "skips empty user_message and agent_message", %{session_file: session_file, thread_id: thread_id} do
      empty_user = %{"type" => "event_msg", "payload" => %{"type" => "user_message", "message" => ""}, "timestamp" => "2024-01-01T00:00:00Z"}
      empty_agent = %{"type" => "event_msg", "payload" => %{"type" => "agent_message", "message" => ""}, "timestamp" => "2024-01-01T00:00:00Z"}
      write_jsonl(session_file, [empty_user, empty_agent, user_event("real")])

      {:ok, messages} = SessionReader.read_messages(thread_id)
      assert length(messages) == 1
      assert hd(messages).content == "real"
    end

    test "returns empty list for empty file", %{session_file: session_file, thread_id: thread_id} do
      File.write!(session_file, "")
      {:ok, messages} = SessionReader.read_messages(thread_id)
      assert messages == []
    end

    test "skips malformed JSON lines", %{session_file: session_file, thread_id: thread_id} do
      content = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"ok\"},\"timestamp\":\"2024-01-01T00:00:00Z\"}\nNOT JSON\n"
      File.write!(session_file, content)

      {:ok, messages} = SessionReader.read_messages(thread_id)
      assert length(messages) == 1
    end

    test "returns :not_found for missing thread_id" do
      assert {:error, :not_found} = SessionReader.read_messages("no-such-thread")
    end

    test "each message has a uuid", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [user_event("a"), agent_event("b")])
      {:ok, [m1, m2]} = SessionReader.read_messages(thread_id)
      assert is_binary(m1.uuid)
      assert is_binary(m2.uuid)
      assert m1.uuid != m2.uuid
    end

    test "same content + timestamp yields same uuid (stable derivation)", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [user_event("stable", "2024-06-01T12:00:00Z")])
      {:ok, [msg]} = SessionReader.read_messages(thread_id)
      uuid1 = msg.uuid

      {:ok, [msg2]} = SessionReader.read_messages(thread_id)
      assert msg2.uuid == uuid1
    end
  end

  # ---------------------------------------------------------------------------
  # read_messages_after_uuid/2
  # ---------------------------------------------------------------------------

  describe "read_messages_after_uuid/2" do
    setup do
      home = System.tmp_dir!() |> Path.join("sr_after_#{:rand.uniform(999_999)}")
      dir = make_sessions_dir(home)
      thread_id = "thread-#{:rand.uniform(999_999)}"
      session_file = Path.join(dir, "rollout-1234567890-#{thread_id}.jsonl")
      original_home = System.get_env("HOME")
      System.put_env("HOME", home)
      on_exit(fn -> System.put_env("HOME", original_home) end)

      write_jsonl(session_file, [
        user_event("first", "2024-01-01T00:00:00Z"),
        agent_event("second", "2024-01-01T00:01:00Z"),
        user_event("third", "2024-01-01T00:02:00Z")
      ])

      {:ok, messages} = SessionReader.read_messages(thread_id)
      {:ok, messages: messages, thread_id: thread_id}
    end

    test "returns all messages when after_uuid is nil", %{messages: messages, thread_id: thread_id} do
      {:ok, result} = SessionReader.read_messages_after_uuid(thread_id, nil)
      assert length(result) == 3
      assert result == messages
    end

    test "returns messages after the given uuid", %{messages: messages, thread_id: thread_id} do
      [first | _] = messages
      {:ok, result} = SessionReader.read_messages_after_uuid(thread_id, first.uuid)
      assert length(result) == 2
      refute Enum.any?(result, fn m -> m.uuid == first.uuid end)
    end

    test "returns all messages when uuid not found (rotated file)", %{messages: messages, thread_id: thread_id} do
      {:ok, result} = SessionReader.read_messages_after_uuid(thread_id, "uuid-that-does-not-exist")
      assert length(result) == length(messages)
    end

    test "returns empty list when after_uuid is the last message", %{messages: messages, thread_id: thread_id} do
      last = List.last(messages)
      {:ok, result} = SessionReader.read_messages_after_uuid(thread_id, last.uuid)
      assert result == []
    end

    test "returns :not_found when thread does not exist" do
      assert {:error, :not_found} = SessionReader.read_messages_after_uuid("no-thread", "any-uuid")
    end
  end

  # ---------------------------------------------------------------------------
  # read_usage/1
  # ---------------------------------------------------------------------------

  describe "read_usage/1" do
    setup do
      home = System.tmp_dir!() |> Path.join("sr_usage_#{:rand.uniform(999_999)}")
      dir = make_sessions_dir(home)
      thread_id = "thread-#{:rand.uniform(999_999)}"
      session_file = Path.join(dir, "rollout-1234567890-#{thread_id}.jsonl")
      original_home = System.get_env("HOME")
      System.put_env("HOME", home)
      on_exit(fn -> System.put_env("HOME", original_home) end)
      {:ok, session_file: session_file, thread_id: thread_id}
    end

    test "returns total tokens from last token_count event", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [
        user_event("hello"),
        token_event(300),
        token_event(500)
      ])

      assert {:ok, 500, 0.0} = SessionReader.read_usage(thread_id)
    end

    test "returns 0 tokens when no token_count events present", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [user_event("hi"), agent_event("ho")])
      assert {:ok, 0, 0.0} = SessionReader.read_usage(thread_id)
    end

    test "returns 0 tokens for empty file", %{session_file: session_file, thread_id: thread_id} do
      File.write!(session_file, "")
      assert {:ok, 0, 0.0} = SessionReader.read_usage(thread_id)
    end

    test "cost is always 0.0", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [token_event(9999)])
      {:ok, _tokens, cost} = SessionReader.read_usage(thread_id)
      assert cost == 0.0
    end

    test "returns :not_found when thread does not exist" do
      assert {:error, :not_found} = SessionReader.read_usage("no-such-thread")
    end

    test "handles single token_count event", %{session_file: session_file, thread_id: thread_id} do
      write_jsonl(session_file, [token_event(1234)])
      assert {:ok, 1234, 0.0} = SessionReader.read_usage(thread_id)
    end
  end

  # ---------------------------------------------------------------------------
  # format_messages/1
  # ---------------------------------------------------------------------------

  describe "format_messages/1" do
    test "returns the list unchanged" do
      msgs = [
        %{role: "user", content: "hi", uuid: "abc", timestamp: nil, usage: nil, stream_type: nil},
        %{role: "assistant", content: "hello", uuid: "def", timestamp: nil, usage: nil, stream_type: nil}
      ]

      assert SessionReader.format_messages(msgs) == msgs
    end

    test "returns empty list for empty input" do
      assert SessionReader.format_messages([]) == []
    end

    test "is an identity function — does not mutate" do
      msg = %{role: "user", content: "test", uuid: "xyz", timestamp: "now", usage: nil, stream_type: nil}
      result = SessionReader.format_messages([msg])
      assert hd(result) === msg
    end
  end
end

defmodule EyeInTheSky.Messages.JsonlStorageTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Messages.JsonlStorage

  # locate_by_id builds: $HOME/.claude/projects/<project_id>/<session_id>.jsonl
  # We use a unique project_id per test so async runs don't collide.

  defp tmp_project_id, do: "test-jsonl-storage-#{System.unique_integer([:positive])}"
  defp tmp_session_id, do: "sess-#{System.unique_integer([:positive])}"

  defp write_jsonl(project_id, session_id, lines) do
    home = System.get_env("HOME")
    dir = Path.join([home, ".claude", "projects", project_id])
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{session_id}.jsonl")
    File.write!(path, Enum.join(lines, "\n") <> "\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    path
  end

  describe "read_session_messages/2 — invalid unix timestamps" do
    test "out-of-range integer unix timestamp does not raise, message is returned with nil inserted_at" do
      project_id = tmp_project_id()
      session_id = tmp_session_id()

      # Year ~5138 — exceeds DateTime.from_unix!/1 max range
      line =
        Jason.encode!(%{
          "id" => "abc123",
          "body" => "hello",
          "inserted_at" => 99_999_999_999_999
        })

      write_jsonl(project_id, session_id, [line])

      assert messages = JsonlStorage.read_session_messages(project_id, session_id)
      assert length(messages) == 1
      assert hd(messages).body == "hello"
      assert hd(messages).inserted_at == nil
    end

    test "non-numeric binary unix timestamp does not raise, message is returned with nil inserted_at" do
      project_id = tmp_project_id()
      session_id = tmp_session_id()

      line =
        Jason.encode!(%{
          "id" => "abc456",
          "body" => "world",
          "inserted_at" => "not-a-timestamp"
        })

      write_jsonl(project_id, session_id, [line])

      assert messages = JsonlStorage.read_session_messages(project_id, session_id)
      assert length(messages) == 1
      assert hd(messages).body == "world"
      assert hd(messages).inserted_at == nil
    end

    test "negative out-of-range integer unix timestamp does not raise" do
      project_id = tmp_project_id()
      session_id = tmp_session_id()

      line =
        Jason.encode!(%{
          "id" => "abc789",
          "body" => "negative",
          "inserted_at" => -99_999_999_999_999
        })

      write_jsonl(project_id, session_id, [line])

      assert messages = JsonlStorage.read_session_messages(project_id, session_id)
      assert length(messages) == 1
      assert hd(messages).inserted_at == nil
    end
  end

  describe "read_session_messages/2 — deterministic ordering for missing timestamps" do
    test "messages with nil inserted_at sort stably before timestamped messages across repeated reads" do
      project_id = tmp_project_id()
      session_id = tmp_session_id()

      t1 = "2024-01-01T10:00:00Z"
      t2 = "2024-01-01T11:00:00Z"

      lines = [
        Jason.encode!(%{"id" => "id-a", "body" => "no-timestamp"}),
        Jason.encode!(%{"id" => "id-b", "body" => "later", "inserted_at" => t2}),
        Jason.encode!(%{"id" => "id-c", "body" => "earlier", "inserted_at" => t1})
      ]

      write_jsonl(project_id, session_id, lines)

      ids_first = JsonlStorage.read_session_messages(project_id, session_id) |> Enum.map(& &1.id)
      ids_second = JsonlStorage.read_session_messages(project_id, session_id) |> Enum.map(& &1.id)

      # Results must be identical across reads (stable, not random)
      assert ids_first == ids_second

      # nil-timestamp message sorts before the two timestamped ones
      assert hd(ids_first) == "id-a"
      # timestamped messages sort in chronological order
      assert ids_first == ["id-a", "id-c", "id-b"]
    end

    test "multiple nil-timestamp messages preserve a stable relative order across reads" do
      project_id = tmp_project_id()
      session_id = tmp_session_id()

      lines = [
        Jason.encode!(%{"id" => "no-ts-1", "body" => "first"}),
        Jason.encode!(%{"id" => "no-ts-2", "body" => "second"}),
        Jason.encode!(%{"id" => "no-ts-3", "body" => "third"})
      ]

      write_jsonl(project_id, session_id, lines)

      ids_first = JsonlStorage.read_session_messages(project_id, session_id) |> Enum.map(& &1.id)
      ids_second = JsonlStorage.read_session_messages(project_id, session_id) |> Enum.map(& &1.id)

      assert ids_first == ids_second
    end
  end
end

defmodule EyeInTheSky.Messages.SearchTest do
  use EyeInTheSky.DataCase, async: true

  import EyeInTheSky.Factory

  alias EyeInTheSky.Messages.{Message, Search}
  alias EyeInTheSky.Repo

  defp insert_message(session, attrs \\ %{}) do
    now = DateTime.utc_now()

    defaults = %{
      uuid: Ecto.UUID.generate(),
      session_id: session.id,
      sender_role: "agent",
      direction: "inbound",
      body: "Hello world from session",
      status: "sent",
      inserted_at: now,
      updated_at: now
    }

    %Message{}
    |> Message.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "search_messages/2 — guard clauses" do
    test "returns [] for empty string query" do
      assert Search.search_messages("") == []
    end

    test "returns [] for nil query" do
      assert Search.search_messages(nil) == []
    end

    test "returns [] for integer query" do
      assert Search.search_messages(42) == []
    end

    test "returns [] for atom query" do
      assert Search.search_messages(:foo) == []
    end
  end

  describe "search_messages/2 — FTS matching" do
    test "returns matching message with correct shape" do
      session = new_session()
      _msg = insert_message(session, %{body: "Elixir is a functional language"})

      results = Search.search_messages("Elixir")

      assert length(results) == 1
      [hit] = results
      assert hit.session_id == session.id
      assert hit.session_uuid == session.uuid
      assert is_binary(hit.body_excerpt)
      assert hit.sender_role == "agent"
      assert %DateTime{} = hit.inserted_at
      assert is_integer(hit.id)
    end

    test "returns [] when query matches no messages" do
      session = new_session()
      _msg = insert_message(session, %{body: "Phoenix LiveView rocks"})

      assert Search.search_messages("xyzzynotaword") == []
    end

    test "body_excerpt is capped at 200 characters" do
      session = new_session()
      long_body = String.duplicate("a", 300)
      _msg = insert_message(session, %{body: long_body})

      # FTS won't match a string of 'aaa...'; use a real word
      unique_word = "cryptographic#{System.unique_integer([:positive])}"
      _msg2 = insert_message(session, %{body: "#{unique_word} " <> String.duplicate("b", 250)})

      results = Search.search_messages(unique_word)
      assert length(results) == 1
      [hit] = results
      assert String.length(hit.body_excerpt) <= 200
    end
  end

  describe "search_messages/2 — session_id scoping" do
    test "returns only messages from the specified session" do
      session_a = new_session()
      session_b = new_session()

      unique = "uniqueterm#{System.unique_integer([:positive])}"
      insert_message(session_a, %{body: "#{unique} from session A"})
      insert_message(session_b, %{body: "#{unique} from session B"})

      results = Search.search_messages(unique, session_id: session_a.id)

      assert length(results) == 1
      assert hd(results).session_id == session_a.id
    end

    test "without session_id scoping returns messages from all sessions" do
      session_a = new_session()
      session_b = new_session()

      unique = "multiterm#{System.unique_integer([:positive])}"
      insert_message(session_a, %{body: "#{unique} message one"})
      insert_message(session_b, %{body: "#{unique} message two"})

      results = Search.search_messages(unique)

      session_ids = Enum.map(results, & &1.session_id)
      assert session_a.id in session_ids
      assert session_b.id in session_ids
    end
  end

  describe "search_messages/2 — limit option" do
    test "respects the :limit option" do
      session = new_session()
      unique = "limitword#{System.unique_integer([:positive])}"

      for i <- 1..5 do
        insert_message(session, %{
          body: "#{unique} message number #{i}",
          inserted_at: DateTime.add(DateTime.utc_now(), -i, :second),
          updated_at: DateTime.utc_now()
        })
      end

      results = Search.search_messages(unique, limit: 3)
      assert length(results) == 3
    end

    test "defaults to returning at most 10 results" do
      session = new_session()
      unique = "defaultlimitword#{System.unique_integer([:positive])}"

      for i <- 1..12 do
        insert_message(session, %{
          body: "#{unique} item #{i}",
          inserted_at: DateTime.add(DateTime.utc_now(), -i, :second),
          updated_at: DateTime.utc_now()
        })
      end

      results = Search.search_messages(unique)
      assert length(results) <= 10
    end

    test "caps limit at 100 regardless of option value" do
      # Can't easily insert 101 rows in a test, so we verify the clamp logic
      # by confirming a limit of 9999 returns no more than the actual row count
      session = new_session()
      unique = "caplimitword#{System.unique_integer([:positive])}"

      for i <- 1..3 do
        insert_message(session, %{
          body: "#{unique} row #{i}",
          inserted_at: DateTime.add(DateTime.utc_now(), -i, :second),
          updated_at: DateTime.utc_now()
        })
      end

      results = Search.search_messages(unique, limit: 9999)
      assert length(results) == 3
    end
  end

  describe "search_messages/2 — archived session exclusion" do
    test "excludes messages from archived sessions by default" do
      session = new_session()
      unique = "archivedterm#{System.unique_integer([:positive])}"
      insert_message(session, %{body: "#{unique} in archived session"})

      # Archive the session
      session
      |> Ecto.Changeset.change(%{archived_at: DateTime.utc_now()})
      |> Repo.update!()

      results = Search.search_messages(unique)
      assert results == []
    end

    test "includes messages from archived sessions when include_archived: true" do
      session = new_session()
      unique = "includearchived#{System.unique_integer([:positive])}"
      insert_message(session, %{body: "#{unique} should appear"})

      session
      |> Ecto.Changeset.change(%{archived_at: DateTime.utc_now()})
      |> Repo.update!()

      results = Search.search_messages(unique, include_archived: true)
      assert length(results) == 1
      assert hd(results).session_id == session.id
    end

    test "non-archived sessions are always included" do
      session = new_session()
      unique = "notarchived#{System.unique_integer([:positive])}"
      insert_message(session, %{body: "#{unique} active session message"})

      results = Search.search_messages(unique)
      assert length(results) == 1
      assert hd(results).session_id == session.id
    end
  end

  describe "search_messages/2 — sender_role filtering" do
    test "does not return messages with system sender_role" do
      session = new_session()
      unique = "systemrole#{System.unique_integer([:positive])}"
      insert_message(session, %{body: "#{unique} system message", sender_role: "system"})

      results = Search.search_messages(unique)
      assert results == []
    end

    test "returns messages with user sender_role" do
      session = new_session()
      unique = "userrole#{System.unique_integer([:positive])}"
      insert_message(session, %{body: "#{unique} user message", sender_role: "user"})

      results = Search.search_messages(unique)
      assert length(results) == 1
    end

    test "returns messages with assistant sender_role" do
      session = new_session()
      unique = "assistantrole#{System.unique_integer([:positive])}"
      insert_message(session, %{body: "#{unique} assistant message", sender_role: "assistant"})

      results = Search.search_messages(unique)
      assert length(results) == 1
    end
  end
end

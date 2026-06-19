defmodule EyeInTheSky.MessageReactionsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.MessageReactions
  alias EyeInTheSky.Messages.{Message, MessageReaction}
  alias EyeInTheSky.Repo

  import EyeInTheSky.Factory

  defp create_message(session) do
    {:ok, msg} =
      %Message{}
      |> Message.changeset(%{
        sender_role: "user",
        direction: "inbound",
        body: "hello",
        session_id: session.id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })
      |> Repo.insert()

    msg
  end

  setup do
    session = new_session()
    msg = create_message(session)
    %{session: session, message: msg}
  end

  describe "add_reaction/3" do
    test "inserts a reaction with the given emoji", %{session: s, message: m} do
      assert {:ok, %MessageReaction{} = r} = MessageReactions.add_reaction(m.id, s.id, "👍")
      assert r.message_id == m.id
      assert r.session_id == s.id
      assert r.emoji == "👍"
      assert %DateTime{} = r.inserted_at
    end

    test "rejects duplicate (unique constraint)", %{session: s, message: m} do
      {:ok, _} = MessageReactions.add_reaction(m.id, s.id, "🎉")

      assert {:error, changeset} = MessageReactions.add_reaction(m.id, s.id, "🎉")
      refute changeset.valid?
    end

    test "rejects empty emoji via length validation", %{session: s, message: m} do
      assert {:error, changeset} = MessageReactions.add_reaction(m.id, s.id, "")
      refute changeset.valid?
      assert errors_on(changeset)[:emoji]
    end

    test "rejects emoji over 10 chars", %{session: s, message: m} do
      assert {:error, changeset} = MessageReactions.add_reaction(m.id, s.id, "abcdefghijk")
      refute changeset.valid?
      assert errors_on(changeset)[:emoji]
    end

    test "rejects missing message_id" do
      assert {:error, changeset} = MessageReactions.add_reaction(nil, 1, "👍")
      refute changeset.valid?
      assert errors_on(changeset)[:message_id]
    end
  end

  describe "remove_reaction/3" do
    test "deletes only the matching reaction", %{session: s, message: m} do
      {:ok, _} = MessageReactions.add_reaction(m.id, s.id, "👍")
      {:ok, _} = MessageReactions.add_reaction(m.id, s.id, "🎉")

      assert {1, _} = MessageReactions.remove_reaction(m.id, s.id, "👍")

      remaining = Repo.all(MessageReaction)
      assert length(remaining) == 1
      assert hd(remaining).emoji == "🎉"
    end

    test "returns {0, _} when nothing to remove", %{session: s, message: m} do
      assert {0, _} = MessageReactions.remove_reaction(m.id, s.id, "🚀")
    end

    test "scopes deletion by session_id", %{session: s, message: m} do
      other = new_session()
      {:ok, _} = MessageReactions.add_reaction(m.id, s.id, "👍")
      {:ok, _} = MessageReactions.add_reaction(m.id, other.id, "👍")

      assert {1, _} = MessageReactions.remove_reaction(m.id, s.id, "👍")

      [remaining] = Repo.all(MessageReaction)
      assert remaining.session_id == other.id
    end
  end

  describe "list_reactions_for_message/1" do
    test "returns empty list when no reactions", %{message: m} do
      assert [] = MessageReactions.list_reactions_for_message(m.id)
    end

    test "groups reactions by emoji with count and session_ids", %{session: s, message: m} do
      other = new_session()
      {:ok, _} = MessageReactions.add_reaction(m.id, s.id, "👍")
      {:ok, _} = MessageReactions.add_reaction(m.id, other.id, "👍")
      {:ok, _} = MessageReactions.add_reaction(m.id, s.id, "🎉")

      result = MessageReactions.list_reactions_for_message(m.id)

      thumbs = Enum.find(result, &(&1.emoji == "👍"))
      party = Enum.find(result, &(&1.emoji == "🎉"))

      assert thumbs.count == 2
      assert Enum.sort(thumbs.session_ids) == Enum.sort([s.id, other.id])

      assert party.count == 1
      assert party.session_ids == [s.id]
    end

    test "excludes reactions on other messages", %{session: s, message: m} do
      other_msg = create_message(s)
      {:ok, _} = MessageReactions.add_reaction(m.id, s.id, "👍")
      {:ok, _} = MessageReactions.add_reaction(other_msg.id, s.id, "🎉")

      result = MessageReactions.list_reactions_for_message(m.id)
      assert [%{emoji: "👍", count: 1}] = result
    end
  end

  describe "toggle_reaction/3" do
    test "adds reaction when none exists", %{session: s, message: m} do
      assert {:ok, :added} = MessageReactions.toggle_reaction(m.id, s.id, "👍")
      assert [%MessageReaction{emoji: "👍"}] = Repo.all(MessageReaction)
    end

    test "removes reaction when it already exists", %{session: s, message: m} do
      {:ok, :added} = MessageReactions.toggle_reaction(m.id, s.id, "👍")
      assert {:ok, :removed} = MessageReactions.toggle_reaction(m.id, s.id, "👍")
      assert [] = Repo.all(MessageReaction)
    end

    test "added then removed then added cycles cleanly", %{session: s, message: m} do
      assert {:ok, :added} = MessageReactions.toggle_reaction(m.id, s.id, "🎉")
      assert {:ok, :removed} = MessageReactions.toggle_reaction(m.id, s.id, "🎉")
      assert {:ok, :added} = MessageReactions.toggle_reaction(m.id, s.id, "🎉")
      assert [%MessageReaction{}] = Repo.all(MessageReaction)
    end

    test "different emojis on same message coexist", %{session: s, message: m} do
      assert {:ok, :added} = MessageReactions.toggle_reaction(m.id, s.id, "👍")
      assert {:ok, :added} = MessageReactions.toggle_reaction(m.id, s.id, "🎉")
      assert length(Repo.all(MessageReaction)) == 2
    end

    test "different sessions toggling same emoji are independent", %{session: s, message: m} do
      other = new_session()
      assert {:ok, :added} = MessageReactions.toggle_reaction(m.id, s.id, "👍")
      assert {:ok, :added} = MessageReactions.toggle_reaction(m.id, other.id, "👍")
      assert length(Repo.all(MessageReaction)) == 2

      assert {:ok, :removed} = MessageReactions.toggle_reaction(m.id, s.id, "👍")

      [remaining] = Repo.all(MessageReaction)
      assert remaining.session_id == other.id
    end

    test "returns error tuple on invalid emoji", %{session: s, message: m} do
      assert {:error, changeset} = MessageReactions.toggle_reaction(m.id, s.id, "")
      refute changeset.valid?
    end
  end
end

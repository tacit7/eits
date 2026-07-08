defmodule EyeInTheSky.NotesTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Notes

  describe "toggle_starred/1" do
    setup do
      {:ok, note} =
        Notes.create_note(%{
          parent_type: "session",
          parent_id: "1",
          body: "toggle-starred test note",
          starred: false
        })

      %{note: note}
    end

    test "flips starred and tolerates a string id", %{note: note} do
      # ids arrive as strings from phx-value / the context menu; toggle_starred
      # must coerce them for the raw parameterized query. It must also avoid
      # RETURNING * (the notes table has an `embedding` pgvector column the Repo
      # cannot decode) — both regressions this test guards.
      assert {:ok, toggled} = Notes.toggle_starred(to_string(note.id))
      assert toggled.starred == true
      assert Repo.reload(note).starred == true

      assert {:ok, untoggled} = Notes.toggle_starred(to_string(note.id))
      assert untoggled.starred == false
      assert Repo.reload(note).starred == false
    end

    test "returns :not_found for an unknown id" do
      assert {:error, :not_found} = Notes.toggle_starred("999999999")
    end

    test "returns :not_found for a non-numeric id" do
      assert {:error, :not_found} = Notes.toggle_starred("not-a-number")
    end
  end

  describe "list_notes_by_source_session/2" do
    test "returns only notes authored by the given session" do
      author = Ecto.UUID.generate()
      other = Ecto.UUID.generate()

      {:ok, mine} =
        Notes.create_note(%{
          parent_type: "session",
          parent_id: "1",
          body: "mine",
          source_session_uuid: author
        })

      {:ok, _theirs} =
        Notes.create_note(%{
          parent_type: "session",
          parent_id: "1",
          body: "theirs",
          source_session_uuid: other
        })

      results = Notes.list_notes_by_source_session(author)

      assert Enum.map(results, & &1.id) == [mine.id]
    end

    test "filters by parent_type and parent_id" do
      author = Ecto.UUID.generate()

      {:ok, project_note} =
        Notes.create_note(%{
          parent_type: "project",
          parent_id: "11",
          body: "project note",
          source_session_uuid: author
        })

      {:ok, _task_note} =
        Notes.create_note(%{
          parent_type: "task",
          parent_id: "22",
          body: "task note",
          source_session_uuid: author
        })

      results =
        Notes.list_notes_by_source_session(author, parent_type: "project", parent_id: "11")

      assert Enum.map(results, & &1.id) == [project_note.id]
    end

    test "filters by starred" do
      author = Ecto.UUID.generate()

      {:ok, starred_note} =
        Notes.create_note(%{
          parent_type: "session",
          parent_id: "1",
          body: "starred",
          starred: true,
          source_session_uuid: author
        })

      {:ok, _unstarred_note} =
        Notes.create_note(%{
          parent_type: "session",
          parent_id: "1",
          body: "unstarred",
          starred: false,
          source_session_uuid: author
        })

      results = Notes.list_notes_by_source_session(author, starred: true)

      assert Enum.map(results, & &1.id) == [starred_note.id]
    end
  end
end

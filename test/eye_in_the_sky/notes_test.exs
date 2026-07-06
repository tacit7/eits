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
end

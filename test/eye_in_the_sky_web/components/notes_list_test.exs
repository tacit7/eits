defmodule EyeInTheSkyWeb.Components.NotesListTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Notes
  alias EyeInTheSky.Projects
  alias EyeInTheSkyWeb.Components.NotesList

  defp build_note(overrides \\ %{}) do
    {:ok, project} =
      Projects.create_project(%{
        name: "test-#{System.unique_integer()}",
        path: "/tmp/test",
        slug: "test-#{System.unique_integer()}"
      })

    {:ok, note} =
      Notes.create_note(
        Map.merge(
          %{
            parent_type: "project",
            parent_id: to_string(project.id),
            body: "# Test note\n\nsome content"
          },
          overrides
        )
      )

    note
  end

  test "renders expand button linking to full editor" do
    note = build_note()

    html =
      render_component(
        &NotesList.notes_list/1,
        notes: [note],
        starred_filter: false,
        search_query: "",
        empty_id: "test-empty",
        editing_note_id: nil,
        current_path: "/notes"
      )

    assert html =~ ~s(/notes/#{note.id}/edit)
    assert html =~ "Open full editor"
  end

  test "expand button encodes return_to from current_path" do
    note = build_note()

    html =
      render_component(
        &NotesList.notes_list/1,
        notes: [note],
        starred_filter: false,
        search_query: "",
        empty_id: "test-empty",
        editing_note_id: nil,
        current_path: "/projects/99/notes"
      )

    assert html =~ "return_to=%2Fprojects%2F99%2Fnotes"
  end
end

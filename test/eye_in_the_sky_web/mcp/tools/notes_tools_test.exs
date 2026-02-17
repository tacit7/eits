defmodule EyeInTheSkyWeb.MCP.Tools.NotesToolsTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.{NoteGet, NoteAdd, NoteSearch}
  alias EyeInTheSkyWeb.Notes

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp make_note(attrs \\ %{}) do
    defaults = %{parent_id: "s1", parent_type: "session", body: "body #{uniq()}"}
    {:ok, note} = Notes.create_note(Map.merge(defaults, attrs))
    note
  end

  defp uniq, do: System.unique_integer([:positive])

  # ---- NoteGet ----

  test "NoteGet: returns note by integer ID string" do
    note = make_note(%{title: "Hello", body: "World"})
    r = NoteGet.execute(%{note_id: to_string(note.id)}, @frame) |> json_result()
    assert r.note_id == to_string(note.id)
    assert r.body == "World"
    assert r.title == "Hello"
  end

  test "NoteGet: error for nonexistent note" do
    r = NoteGet.execute(%{note_id: "999999"}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "Note not found")
  end

  test "NoteGet: includes parent_id and parent_type" do
    note = make_note(%{parent_id: "p42", parent_type: "session"})
    r = NoteGet.execute(%{note_id: to_string(note.id)}, @frame) |> json_result()
    assert r.parent_id == "p42"
    assert r.parent_type == "session"
  end

  # ---- NoteAdd ----

  test "NoteAdd: creates note with required fields" do
    r = NoteAdd.execute(%{parent_id: "a1", parent_type: "agent", body: "note body"}, @frame) |> json_result()
    assert r.success == true
    assert r.message == "Note created"
    assert is_integer(r.id)
  end

  test "NoteAdd: accepts optional title and starred" do
    r = NoteAdd.execute(%{
      parent_id: "s1", parent_type: "session", body: "body",
      title: "My Title", starred: 1
    }, @frame) |> json_result()
    assert r.success == true
  end

  test "NoteAdd: defaults starred to 0" do
    r = NoteAdd.execute(%{parent_id: "s1", parent_type: "session", body: "body"}, @frame) |> json_result()
    assert r.success == true
    note = Notes.get_note!(r.id)
    assert note.starred == 0
  end

  # ---- NoteSearch ----

  test "NoteSearch: returns matching notes" do
    make_note(%{title: "findme#{uniq()}", body: "findme unique body"})
    # Use empty query to list all; unique content already in DB
    r = NoteSearch.execute(%{query: "findme"}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.results)
  end

  test "NoteSearch: empty list when nothing matches" do
    r = NoteSearch.execute(%{query: "zzznomatchxyzqwerty"}, @frame) |> json_result()
    assert r.success == true
    assert r.results == []
  end

  test "NoteSearch: respects limit" do
    for _ <- 1..5, do: make_note(%{title: "limtest", body: "limtest body #{uniq()}"})
    r = NoteSearch.execute(%{query: "limtest", limit: 2}, @frame) |> json_result()
    assert length(r.results) <= 2
  end

  test "NoteSearch: result items have expected fields" do
    make_note(%{title: "fieldchk", body: "fieldchk body", parent_id: "s1", parent_type: "session"})
    r = NoteSearch.execute(%{query: "fieldchk"}, @frame) |> json_result()
    assert length(r.results) >= 1
    item = hd(r.results)
    assert Map.has_key?(item, :id)
    assert Map.has_key?(item, :body)
    assert Map.has_key?(item, :parent_id)
    assert Map.has_key?(item, :parent_type)
  end
end

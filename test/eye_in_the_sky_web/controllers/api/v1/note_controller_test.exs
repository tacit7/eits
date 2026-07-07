defmodule EyeInTheSkyWeb.Api.V1.NoteControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Notes

  import EyeInTheSky.Factory

  defp create_note(overrides \\ %{}) do
    {:ok, note} =
      Notes.create_note(
        Map.merge(
          %{
            parent_id: to_string(uniq()),
            parent_type: "session",
            body: "Test note body #{uniq()}"
          },
          overrides
        )
      )

    note
  end

  # ---- GET /api/v1/notes ----

  describe "GET /api/v1/notes" do
    test "returns a list of notes", %{conn: conn} do
      create_note()
      conn = get(conn, ~p"/api/v1/notes")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["results"])
    end

    test "searches by q param", %{conn: conn} do
      unique_body = "UniqueNoteBodyABC#{uniq()}"
      create_note(%{body: unique_body})
      conn = get(conn, ~p"/api/v1/notes?q=#{unique_body}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert Enum.any?(resp["results"], &String.contains?(&1["body"], "UniqueNoteBodyABC"))
    end

    test "filters by session_id", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      create_note(%{parent_id: to_string(session.id), parent_type: "session"})

      conn = get(conn, ~p"/api/v1/notes?session_id=#{session.uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["results"] != []
    end

    test "respects limit param", %{conn: conn} do
      for _ <- 1..5, do: create_note()
      conn = get(conn, ~p"/api/v1/notes?limit=2")
      resp = json_response(conn, 200)

      assert length(resp["results"]) <= 2
    end

    test "filters by source_session_uuid", %{conn: conn} do
      author_uuid = Ecto.UUID.generate()
      other_uuid = Ecto.UUID.generate()
      create_note(%{source_session_uuid: author_uuid})
      create_note(%{source_session_uuid: other_uuid})

      conn = get(conn, ~p"/api/v1/notes?source_session_uuid=#{author_uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert length(resp["results"]) == 1
      assert hd(resp["results"])["source_session_uuid"] == author_uuid
    end
  end

  # ---- GET /api/v1/notes/:id ----

  describe "GET /api/v1/notes/:id" do
    test "returns a note by id", %{conn: conn} do
      note = create_note(%{title: "My Note Title"})
      conn = get(conn, ~p"/api/v1/notes/#{note.id}")
      resp = json_response(conn, 200)

      assert resp["note_id"] == to_string(note.id)
      assert resp["body"] == note.body
      assert resp["title"] == "My Note Title"
    end

    test "returns 404 for missing note", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/notes/9999999")
      assert json_response(conn, 404)["error"] == "Note not found"
    end
  end

  # ---- POST /api/v1/notes ----

  describe "POST /api/v1/notes" do
    test "creates a note with valid params", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/notes", %{
          "parent_type" => "session",
          "parent_id" => "123",
          "body" => "This is my note"
        })

      resp = json_response(conn, 201)

      assert resp["body"] == "This is my note"
      assert resp["parent_type"] == "session"
    end

    test "normalizes plural parent_type", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/notes", %{
          "parent_type" => "sessions",
          "parent_id" => "456",
          "body" => "note body"
        })

      resp = json_response(conn, 201)
      assert resp["parent_type"] == "session"
    end

    test "creates note with optional title", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/notes", %{
          "parent_type" => "task",
          "parent_id" => "789",
          "title" => "Decision",
          "body" => "We decided to use REST"
        })

      resp = json_response(conn, 201)
      assert resp["body"] == "We decided to use REST"
    end

    test "returns 422 when parent_type is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/notes", %{
          "parent_type" => "invalid_type",
          "parent_id" => "1",
          "body" => "body"
        })

      resp = json_response(conn, 422)
      assert resp["error"] == "Failed to create note"
    end

    test "auto-stamps source_session_uuid from x-eits-session header", %{conn: conn} do
      session_uuid = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("x-eits-session", session_uuid)
        |> post(~p"/api/v1/notes", %{
          "parent_type" => "session",
          "parent_id" => "123",
          "body" => "authored by agent"
        })

      resp = json_response(conn, 201)
      assert resp["source_session_uuid"] == session_uuid
    end

    test "explicit source_session_uuid param wins over header", %{conn: conn} do
      header_uuid = Ecto.UUID.generate()
      explicit_uuid = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("x-eits-session", header_uuid)
        |> post(~p"/api/v1/notes", %{
          "parent_type" => "session",
          "parent_id" => "123",
          "body" => "explicit wins",
          "source_session_uuid" => explicit_uuid
        })

      resp = json_response(conn, 201)
      assert resp["source_session_uuid"] == explicit_uuid
    end

    test "source_session_uuid is nil when no header or param present", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/notes", %{
          "parent_type" => "session",
          "parent_id" => "123",
          "body" => "no attribution"
        })

      resp = json_response(conn, 201)
      assert resp["source_session_uuid"] == nil
    end
  end

  # ---- PATCH /api/v1/notes/:id ----

  describe "PATCH /api/v1/notes/:id" do
    test "updates note body", %{conn: conn} do
      note = create_note()
      conn = patch(conn, ~p"/api/v1/notes/#{note.id}", %{"body" => "Updated body"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["body"] == "Updated body"
    end

    test "updates note title", %{conn: conn} do
      note = create_note()
      conn = patch(conn, ~p"/api/v1/notes/#{note.id}", %{"title" => "New title"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["title"] == "New title"
    end

    test "toggles starred when starred param present", %{conn: conn} do
      note = create_note()
      conn = patch(conn, ~p"/api/v1/notes/#{note.id}", %{"starred" => 1})
      resp = json_response(conn, 200)

      assert resp["success"] == true
    end

    test "returns 404 for missing note", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/notes/9999999", %{"body" => "x"})
      assert json_response(conn, 404)["error"] == "Note not found"
    end
  end
end

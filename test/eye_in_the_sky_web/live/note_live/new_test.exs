defmodule EyeInTheSkyWeb.NoteLive.NewTest do
  use EyeInTheSkyWeb.LiveViewTest

  import EyeInTheSkyWeb.NoteLive.Helpers

  alias EyeInTheSky.Notes

  describe "NoteLive.New - mount" do
    test "initializes with default values", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "New Note"
      assert html =~ "Untitled note"
    end

    test "sets page title to 'New Note'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      assert lv |> element("html") |> render() =~ "New Note"
    end

    test "sets default parent_type to 'system'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      assert lv.assigns.parent_type == "system"
    end

    test "sets default parent_id to '0'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      assert lv.assigns.parent_id == "0"
    end

    test "sets return_to to '/notes' by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      assert lv.assigns.return_to == "/notes"
    end
  end

  describe "NoteLive.New - handle_params" do
    test "sets parent_type from params if valid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=task&parent_id=123")

      assert lv.assigns.parent_type == "task"
      assert lv.assigns.parent_id == "123"
    end

    test "defaults to 'system' if parent_type is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=invalid&parent_id=123")

      assert lv.assigns.parent_type == "system"
    end

    test "accepts all valid parent types", %{conn: conn} do
      valid_types = ["session", "task", "agent", "project", "system"]

      for parent_type <- valid_types do
        {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=#{parent_type}")
        assert lv.assigns.parent_type == parent_type
      end
    end

    test "sets parent_id from params", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_id=999")

      assert lv.assigns.parent_id == "999"
    end

    test "defaults parent_id to '0' if missing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=task")

      assert lv.assigns.parent_id == "0"
    end

    test "updates return_to from params if provided", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?return_to=/projects")

      assert lv.assigns.return_to == "/projects"
    end

    test "sanitizes unsafe return_to paths", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?return_to=javascript:alert('xss')")

      # safe_return_to should return /notes for unsafe paths
      assert lv.assigns.return_to == "/notes"
    end
  end

  describe "NoteLive.New - handle_event: update_title" do
    test "updates title on blur", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      lv |> element("input[name='title']") |> render_blur(%{"value" => "My Note"})

      assert lv.assigns.title == "My Note"
    end

    test "trims whitespace from title", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      lv |> element("input[name='title']") |> render_blur(%{"value" => "  Trimmed  "})

      assert lv.assigns.title == "Trimmed"
    end

    test "handles empty title", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      lv |> element("input[name='title']") |> render_blur(%{"value" => ""})

      assert lv.assigns.title == ""
    end
  end

  describe "NoteLive.New - handle_event: note_saved" do
    setup do
      # Create a clean test to isolate note creation
      %{}
    end

    test "creates a note with valid body", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=system")

      # Update title
      lv |> element("input[name='title']") |> render_blur(%{"value" => "Test Note"})

      # Simulate the JS hook sending the save event
      lv |> render_hook("note_saved", %{"body" => "Test note body"})

      # Verify the note was created by checking if we navigated away
      assert_push_navigate(lv, ~p"/notes")
    end

    test "rejects empty note body", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      lv |> render_hook("note_saved", %{"body" => ""})

      assert lv |> element(".alert") |> render() =~ "Note body cannot be empty"
    end

    test "rejects note body with only whitespace", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new")

      lv |> render_hook("note_saved", %{"body" => "   \n\t  "})

      assert lv |> element(".alert") |> render() =~ "Note body cannot be empty"
    end

    test "creates note with title and body", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=task&parent_id=42")

      lv |> element("input[name='title']") |> render_blur(%{"value" => "Titled Note"})
      lv |> render_hook("note_saved", %{"body" => "Important content"})

      # Verify navigation
      assert_push_navigate(lv, ~p"/notes")
    end

    test "creates note for all parent types", %{conn: conn} do
      parent_types = ["session", "task", "agent", "project", "system"]

      for parent_type <- parent_types do
        {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=#{parent_type}")

        lv |> render_hook("note_saved", %{"body" => "Test body"})

        assert_push_navigate(lv, ~p"/notes")
      end
    end

    test "respects custom return_to on successful creation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?return_to=/dashboard")

      lv |> render_hook("note_saved", %{"body" => "Test body"})

      assert_push_navigate(lv, ~p"/dashboard")
    end

    test "shows error flash on creation failure", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=invalid_type&parent_id=999")

      # Try to create note with invalid parent_type
      lv |> render_hook("note_saved", %{"body" => "Test body"})

      # Should show error (invalid parent_type or parent_id combo)
      render = render(lv)
      # The handler shows "Failed to create note" for any error
      assert render =~ "Failed to create note" or render =~ "cannot be empty"
    end
  end

  describe "NoteLive.New - rendering" do
    test "renders editor section with hook", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "phx-hook=\"NoteFullEditor\""
      assert html =~ "id=\"note-full-editor-new\""
    end

    test "renders title input", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "id=\"note-title-input\""
      assert html =~ "placeholder=\"Untitled note\""
    end

    test "renders save button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "id=\"note-save-btn\""
      assert html =~ "Save"
    end

    test "renders status bar", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "id=\"note-editor-status\""
      assert html =~ "Ln 1, Col 1"
    end

    test "renders back link to notes", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "Notes"
    end

    test "renders keyboard shortcuts hint", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "Esc to go back"
      assert html =~ "⌘S to save"
    end

    test "renders markdown indicator", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new")

      assert html =~ "Markdown"
    end

    test "back link uses return_to", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/notes/new?return_to=/tasks")

      assert html =~ "/tasks"
    end
  end

  describe "NoteLive.New - integration" do
    test "complete flow: mount → update title → save note → navigate", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notes/new?parent_type=task&parent_id=123&return_to=/my-page")

      # Verify initial state
      assert lv.assigns.parent_type == "task"
      assert lv.assigns.parent_id == "123"
      assert lv.assigns.return_to == "/my-page"
      assert lv.assigns.title == ""

      # Update title
      lv |> element("input[name='title']") |> render_blur(%{"value" => "Integration Test Note"})

      assert lv.assigns.title == "Integration Test Note"

      # Save note
      lv |> render_hook("note_saved", %{"body" => "Test body content"})

      # Verify navigation to custom return_to
      assert_push_navigate(lv, ~p"/my-page")
    end
  end
end

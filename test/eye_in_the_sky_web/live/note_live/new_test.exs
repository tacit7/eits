defmodule EyeInTheSkyWeb.NoteLive.NewTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Notes

  setup do
    Application.put_env(:eye_in_the_sky, :disable_auth, true)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :disable_auth) end)
    :ok
  end

  describe "mount and render" do
    test "renders the new note page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/notes/new")

      assert html =~ "Untitled note"
    end

    test "renders title input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      assert has_element?(view, "input#note-title-input")
    end

    test "renders save button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      assert has_element?(view, "button#note-save-btn")
    end

    test "renders editor hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      assert has_element?(view, "#note-full-editor-new[phx-hook='NoteFullEditor']")
    end

    test "renders status bar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      assert has_element?(view, "#note-editor-status")
      assert render(view) =~ "Ln 1, Col 1"
    end

    test "renders keyboard shortcut hints", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/notes/new")

      assert html =~ "Esc to go back"
      assert html =~ "⌘S to save"
    end

    test "renders markdown indicator", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/notes/new")

      assert html =~ "Markdown"
    end

    test "back link defaults to /notes", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/notes/new")

      assert html =~ ~s(href="/notes")
    end

    test "back link uses return_to parameter", %{conn: conn} do
      # /projects/1/notes is a whitelisted path in safe_return_to/1
      {:ok, _view, html} = live(conn, ~p"/notes/new?return_to=/projects/1/notes")

      assert html =~ ~s(/projects/1/notes)
    end

    test "rejects unsafe return_to (falls back to /notes)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/notes/new?return_to=javascript:alert(1)")

      assert html =~ ~s(href="/notes")
    end
  end

  describe "handle_event: update_title" do
    test "updates title on blur", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      # phx-blur="update_title" — must send event name, not CSS selector
      render_blur(view, "update_title", %{"value" => "My Note"})

      assert has_element?(view, "input#note-title-input")
    end

    test "accepts whitespace-only title (trimmed to empty internally)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      render_blur(view, "update_title", %{"value" => "   "})

      assert has_element?(view, "input#note-title-input")
    end
  end

  describe "handle_event: note_saved" do
    test "rejects empty body with error flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      render_hook(view, "note_saved", %{"body" => ""})

      assert render(view) =~ "Note body cannot be empty"
    end

    test "rejects whitespace-only body with error flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notes/new")

      render_hook(view, "note_saved", %{"body" => "   \n\t  "})

      assert render(view) =~ "Note body cannot be empty"
    end

    test "creates note with valid body and navigates", %{conn: conn} do
      count_before = length(Notes.list_notes_filtered())

      {:ok, view, _html} = live(conn, ~p"/notes/new?parent_type=system")

      assert {:error, {:live_redirect, %{to: "/notes"}}} =
               render_hook(view, "note_saved", %{"body" => "A valid note body"})

      assert length(Notes.list_notes_filtered()) == count_before + 1
    end

    test "creates note for each valid parent_type", %{conn: conn} do
      valid_types = ["session", "task", "agent", "project", "system"]

      for parent_type <- valid_types do
        {:ok, view, _html} = live(conn, ~p"/notes/new?parent_type=#{parent_type}")

        result = render_hook(view, "note_saved", %{"body" => "Test body for #{parent_type}"})

        assert {:error, {:live_redirect, %{to: "/notes"}}} = result
      end
    end

    test "navigates to custom return_to after save", %{conn: conn} do
      # /projects/1/notes is whitelisted in safe_return_to/1; /tasks would be rejected
      {:ok, view, _html} = live(conn, ~p"/notes/new?return_to=/projects/1/notes")

      assert {:error, {:live_redirect, %{to: "/projects/1/notes"}}} =
               render_hook(view, "note_saved", %{"body" => "Note content"})
    end

    test "invalid parent_type falls back to 'system'", %{conn: conn} do
      count_before = length(Notes.list_notes_filtered())

      {:ok, view, _html} = live(conn, ~p"/notes/new?parent_type=nonsense")

      # parent_type "nonsense" falls back to "system"; note saves and redirects
      assert {:error, {:live_redirect, _}} =
               render_hook(view, "note_saved", %{"body" => "Test body"})

      assert length(Notes.list_notes_filtered()) > count_before
    end
  end

  describe "handle_params" do
    test "accepts all valid parent types without crashing", %{conn: conn} do
      valid_types = ["session", "task", "agent", "project", "system"]

      for parent_type <- valid_types do
        {:ok, _view, html} = live(conn, ~p"/notes/new?parent_type=#{parent_type}")

        # All valid types should render the page normally
        assert html =~ "note-title-input"
      end
    end

    test "falls back to default on invalid parent_type", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/notes/new?parent_type=invalid")

      # Page still renders
      assert html =~ "note-title-input"
    end

    test "accepts parent_id param", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/notes/new?parent_type=task&parent_id=42")

      assert html =~ "note-title-input"
    end
  end
end

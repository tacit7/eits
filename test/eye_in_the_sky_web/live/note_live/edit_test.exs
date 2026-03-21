defmodule EyeInTheSkyWeb.NoteLive.EditTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Notes, Projects}

  setup do
    Application.put_env(:eye_in_the_sky, :disable_auth, true)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :disable_auth) end)
    :ok
  end

  defp create_note(overrides \\ %{}) do
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
            body: "# Hello\n\nWorld",
            title: "Test Note"
          },
          overrides
        )
      )

    note
  end

  describe "mount and render" do
    test "renders editor page with note title", %{conn: conn} do
      note = create_note()
      {:ok, view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      assert html =~ "Test Note"
      assert has_element?(view, "input[name='title']")
      assert has_element?(view, "[data-body]")
    end

    test "404 redirects when note does not exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/notes"}}} =
               live(conn, ~p"/notes/99999999/edit")
    end

    test "return_to defaults to /notes when not provided", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      assert html =~ "href=\"/notes\""
    end

    test "return_to accepts valid project notes path", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit?return_to=/projects/1/notes")

      assert html =~ "href=\"/projects/1/notes\""
    end

    test "return_to rejects external URLs", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit?return_to=http://evil.com")

      # Falls back to /notes
      assert html =~ "href=\"/notes\""
    end

    test "renders parent context badge for project note", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      assert html =~ "Project"
    end
  end

  describe "note_saved event" do
    test "saves body and shows saved state", %{conn: conn} do
      note = create_note()
      {:ok, view, _html} = live(conn, ~p"/notes/#{note.id}/edit")

      render_hook(view, "note_saved", %{"body" => "# Updated\n\nNew content"})

      html = render(view)
      assert html =~ "Saved"

      updated = Notes.get_note!(note.id)
      assert updated.body == "# Updated\n\nNew content"
    end
  end

  describe "update_title event" do
    test "saves non-blank title", %{conn: conn} do
      note = create_note()
      {:ok, view, _html} = live(conn, ~p"/notes/#{note.id}/edit")

      render_hook(view, "update_title", %{"value" => "  New Title  "})

      updated = Notes.get_note!(note.id)
      assert updated.title == "New Title"
    end

    test "ignores blank title", %{conn: conn} do
      note = create_note(%{title: "Original"})
      {:ok, view, _html} = live(conn, ~p"/notes/#{note.id}/edit")

      render_hook(view, "update_title", %{"value" => "   "})

      updated = Notes.get_note!(note.id)
      assert updated.title == "Original"
    end
  end
end

defmodule EyeInTheSkyWeb.ProjectLive.FilesTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_project_with_dir do
    tmp_dir = Path.join(System.tmp_dir!(), "eits_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    {:ok, project} =
      Projects.create_project(%{name: "Test Project", path: tmp_dir})

    {project, tmp_dir}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "file_changed event" do
    test "saves file content to disk", %{conn: conn} do
      {project, dir} = create_project_with_dir()
      File.write!(Path.join(dir, "hello.ex"), "# old")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=hello.ex")

      render_hook(view, "file_changed", %{"content" => "# new content"})

      assert File.read!(Path.join(dir, "hello.ex")) == "# new content"
    end

    test "handle_params rejects path traversal via ../", %{conn: conn} do
      {project, dir} = create_project_with_dir()

      # Create a file outside project root
      parent = Path.dirname(dir)
      secret = Path.join(parent, "secret.txt")
      File.write!(secret, "do not touch")

      # Navigate to a ../ path — handle_params should reject it
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=../secret.txt")

      # Should show access denied error, file_content should be nil (no file loaded)
      assert render(view) =~ "Access denied"

      # The secret file should be untouched
      assert File.read!(secret) == "do not touch"
    end

    test "returns error flash on write failure", %{conn: conn} do
      {project, dir} = create_project_with_dir()
      file_path = Path.join(dir, "readonly.ex")
      File.write!(file_path, "content")

      # Make file read-only to cause write failure
      File.chmod!(file_path, 0o444)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=readonly.ex")
      render_hook(view, "file_changed", %{"content" => "new"})

      assert has_element?(view, "[role='alert']") or render(view) =~ "Save failed"

      # Restore permissions for cleanup
      File.chmod!(file_path, 0o644)
    end
  end
end

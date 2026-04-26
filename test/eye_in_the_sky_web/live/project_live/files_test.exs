defmodule EyeInTheSkyWeb.ProjectLive.FilesTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_project_with_dir do
    tmp_dir = Path.join(System.tmp_dir!(), "eits_test_#{System.unique_integer([:positive])}")
    # Clean up any leftovers from killed test runs before creating fresh
    File.rm_rf(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

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

      render_hook(view, "file_save", %{"content" => "# new content"})

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

    test "handle_params rejects symlink escape", %{conn: conn} do
      {project, dir} = create_project_with_dir()

      # Create a file outside project root and a symlink inside pointing to it
      parent = Path.dirname(dir)
      secret = Path.join(parent, "secret_symlink.txt")
      File.write!(secret, "do not touch")

      link_path = Path.join(dir, "escape_link.txt")
      File.ln_s!(secret, link_path)

      # Navigate to the symlink — path_within? resolves it and should reject
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=escape_link.txt")

      # File should not be loaded since realpath resolves outside project
      assert render(view) =~ "Access denied"
      assert File.read!(secret) == "do not touch"
    end

    test "navigating to path=. (Back from top-level file) shows root listing", %{conn: conn} do
      # When viewing a top-level file like "hello.ex", the Back link computes
      # Path.dirname("hello.ex") = "." and patches to ?path=.
      # path_within?(project_root, project_root) must be true so we get the listing.
      {project, dir} = create_project_with_dir()
      File.write!(Path.join(dir, "hello.ex"), "# hello")
      File.write!(Path.join(dir, "world.ex"), "# world")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=.")

      html = render(view)
      # Root directory listing should load — no Access denied
      refute html =~ "Access denied"
      assert html =~ "hello.ex"
    end

    test "returns error flash on write failure", %{conn: conn} do
      {project, dir} = create_project_with_dir()
      file_path = Path.join(dir, "readonly.ex")
      File.write!(file_path, "content")

      # Make file read-only to cause write failure
      File.chmod!(file_path, 0o444)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=readonly.ex")
      render_hook(view, "file_save", %{"content" => "new"})

      assert has_element?(view, "[role='alert']") or render(view) =~ "Save failed"

      # Restore permissions for cleanup
      File.chmod!(file_path, 0o644)
    end
  end

  describe "handle_params — nil project guard" do
    test "non-integer project id redirects to root instead of crashing", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/projects/notanid/files")
    end
  end

  describe "handle_params — error paths" do
    test "non-existent file path assigns an error", %{conn: conn} do
      {project, _dir} = create_project_with_dir()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=does_not_exist.ex")

      html = render(view)
      # Linux realpath succeeds for non-existent paths (path_within? -> true -> "File not found")
      # macOS realpath fails for non-existent paths (path_within? -> false -> "Access denied")
      assert html =~ "File not found" or html =~ "Access denied"
    end

    test "directory path loads listing without error", %{conn: conn} do
      {project, dir} = create_project_with_dir()
      subdir = Path.join(dir, "src")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "app.ex"), "# app")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=src")

      html = render(view)
      refute html =~ "Access denied"
      assert html =~ "app.ex"
    end

    test "valid file path renders content pane without error", %{conn: conn} do
      {project, dir} = create_project_with_dir()
      File.write!(Path.join(dir, "main.ex"), "defmodule Main, do: nil")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/files?path=main.ex")

      html = render(view)
      refute html =~ "Access denied"
      refute html =~ "No files"
    end
  end
end

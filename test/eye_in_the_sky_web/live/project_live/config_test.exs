defmodule EyeInTheSkyWeb.ProjectLive.ConfigTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EyeInTheSky.Factory

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Workspaces

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_project_with_claude_dir(workspace_id) do
    tmp_dir = Path.join(System.tmp_dir!(), "eits_cfg_test_#{System.unique_integer([:positive])}")
    claude_dir = Path.join(tmp_dir, ".claude")
    File.mkdir_p!(claude_dir)

    {:ok, project} =
      Projects.create_project(%{
        name: "Config Test Project",
        path: tmp_dir,
        workspace_id: workspace_id
      })

    {project, tmp_dir, claude_dir}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "file_changed event" do
    @tag :skip
    test "saves config file content to disk", %{conn: conn, user: user} do
      workspace = Workspaces.default_workspace_for_user!(user)
      {project, _dir, claude_dir} = create_project_with_claude_dir(workspace.id)
      File.write!(Path.join(claude_dir, "settings.json"), "{}")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/config?mode=list&path=settings.json")

      render_hook(view, "file_changed", %{"content" => ~s({"key": "value"})})

      assert File.read!(Path.join(claude_dir, "settings.json")) == ~s({"key": "value"})
    end

    test "handle_params rejects path traversal via ../", %{conn: conn, user: user} do
      workspace = Workspaces.default_workspace_for_user!(user)
      {project, dir, _claude_dir} = create_project_with_claude_dir(workspace.id)

      # Create a file outside .claude/
      secret = Path.join(dir, "secret.txt")
      File.write!(secret, "do not touch")

      # Navigate to ../secret.txt — handle_params should reject
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/config?mode=list&path=../secret.txt")

      assert render(view) =~ "Access denied"
      assert File.read!(secret) == "do not touch"
    end

    test "handle_params rejects symlink escape via resolve_list_target", %{conn: conn, user: user} do
      workspace = Workspaces.default_workspace_for_user!(user)
      {project, dir, claude_dir} = create_project_with_claude_dir(workspace.id)

      # Create a secret file outside .claude/
      secret = Path.join(dir, "secret.txt")
      File.write!(secret, "do not touch")

      # Plant a symlink inside .claude/ that points outside
      File.ln_s!(secret, Path.join(claude_dir, "escape.txt"))

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/config?mode=list&path=escape.txt")

      assert render(view) =~ "Access denied"
      assert File.read!(secret) == "do not touch"
    end

    test "read error in list mode clears the directory listing", %{conn: conn, user: user} do
      # ProjectLive.Config (list mode) always clears :files when navigating to a
      # file path, regardless of whether the read succeeds or fails. This test
      # asserts that pre-refactor behavior is preserved.
      workspace = Workspaces.default_workspace_for_user!(user)
      {project, _dir, claude_dir} = create_project_with_claude_dir(workspace.id)

      # Create a readable file first so the listing is populated
      File.write!(Path.join(claude_dir, "settings.json"), "{}")
      locked = Path.join(claude_dir, "locked.txt")
      File.write!(locked, "content")
      File.chmod!(locked, 0o000)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/config?mode=list&path=locked.txt")

      html = render(view)
      # Directory listing is cleared (file navigation clears :files in list mode)
      refute html =~ "settings.json"
      # Error is shown
      assert html =~ "Failed to"

      # Restore permissions for cleanup
      File.chmod!(locked, 0o644)
    end
  end

  describe "workspace switching" do
    test "opens config page for a project in another workspace", %{conn: conn, user: user} do
      current_workspace = Workspaces.default_workspace_for_user!(user)
      other_user = user_fixture()
      other_workspace = Workspaces.default_workspace_for_user!(other_user)
      n = uniq()

      {:ok, foreign_project} =
        Projects.create_project(%{
          name: "Foreign Config #{n}",
          slug: "foreign-config-#{n}",
          path: "/tmp/foreign-config-#{n}",
          workspace_id: other_workspace.id
        })

      assert current_workspace.id != other_workspace.id

      {:ok, view, html} = live(conn, ~p"/projects/#{foreign_project.id}/config")

      assert html =~ foreign_project.name
      refute has_element?(view, "#flash-error", "Project not found")
    end
  end
end

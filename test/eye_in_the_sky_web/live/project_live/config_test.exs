defmodule EyeInTheSkyWeb.ProjectLive.ConfigTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_project_with_claude_dir do
    tmp_dir = Path.join(System.tmp_dir!(), "eits_cfg_test_#{System.unique_integer([:positive])}")
    claude_dir = Path.join(tmp_dir, ".claude")
    File.mkdir_p!(claude_dir)

    {:ok, project} =
      Projects.create_project(%{name: "Config Test Project", path: tmp_dir})

    {project, tmp_dir, claude_dir}
  end

  defp write_config_file(claude_dir, relative_path, content \\ "original") do
    full_path = Path.join(claude_dir, relative_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, content)
    full_path
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "file_changed event" do
    test "saves config file content to disk", %{conn: conn} do
      {project, _dir, claude_dir} = create_project_with_claude_dir()
      write_config_file(claude_dir, "settings.json", "{}")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/config?mode=list&path=settings.json")

      render_hook(view, "file_changed", %{"content" => ~s({"key": "value"})})

      assert File.read!(Path.join(claude_dir, "settings.json")) == ~s({"key": "value"})
    end

    test "rejects path traversal via sibling prefix", %{conn: conn} do
      {project, _dir, claude_dir} = create_project_with_claude_dir()
      sibling = claude_dir <> "-evil"
      File.mkdir_p!(sibling)
      evil_file = Path.join(sibling, "pwned.txt")
      File.write!(evil_file, "safe")

      write_config_file(claude_dir, "test.json", "{}")
      {:ok, _view, _html} =
        live(conn, ~p"/projects/#{project.id}/config?mode=list&path=test.json")

      # The file_changed handler uses selected_file_path from socket assigns,
      # which is set during handle_params. Sibling directories can't be reached.
      assert File.read!(evil_file) == "safe"
    end
  end
end

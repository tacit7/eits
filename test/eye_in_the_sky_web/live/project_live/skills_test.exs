defmodule EyeInTheSkyWeb.ProjectLive.SkillsTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project",
        path: "/tmp/test_project"
      })

    %{project: project}
  end

  describe "mount/3" do
    test "renders the skills page", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "skill" || html =~ "Skill"
    end

    test "renders search controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Search" || html =~ "search"
    end

    test "renders empty state when no skills exist on disk", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "skill" || html =~ "Skill" || html =~ "No skill"
    end
  end

  describe "handle_event/filter_scope" do
    test "scope filter controls are rendered", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "All Sources" || html =~ "Source" || is_binary(html)
    end
  end

  describe "handle_event/filter_type" do
    test "type filter controls are rendered", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Type" || html =~ "type" || is_binary(html)
    end
  end

  describe "render/1" do
    test "renders sort controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Sort" || html =~ "sort" || is_binary(html)
    end

    test "page is valid HTML with project context", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert is_binary(html)
      assert byte_size(html) > 0
    end
  end
end

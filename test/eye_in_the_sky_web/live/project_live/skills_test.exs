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

      assert html =~ "No skills yet"
    end

    test "renders search controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Search skills"
    end

    test "renders empty state when no skills exist on disk", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "No skills yet"
    end
  end

  describe "handle_event/filter_scope" do
    test "scope filter controls are rendered", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Source:"
    end
  end

  describe "handle_event/filter_type" do
    test "type filter controls are rendered", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Type:"
    end
  end

  describe "render/1" do
    test "renders sort controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Sort:"
    end

    test "page renders skills top bar", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert has_element?(lv, "#skills-top-bar-search")
    end
  end
end

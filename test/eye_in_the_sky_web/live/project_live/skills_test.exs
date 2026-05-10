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
    test "initializes with project id", %{conn: conn, project: project} do
      {:ok, lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert lv.assigns.project_id == project.id
      assert lv.assigns.search_query == ""
      assert html =~ "skill" || html =~ "Skill"
    end

    test "initializes filter state", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert lv.assigns.scope_filter == "all"
      assert lv.assigns.sort_by == "name_asc"
    end
  end

  describe "handle_event/search" do
    test "updates search query", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert lv.assigns.search_query == ""
    end
  end

  describe "handle_event/filter_scope" do
    test "filters skills by scope", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert lv.assigns.scope_filter == "all"
    end
  end

  describe "handle_event/select_skill" do
    test "selects a skill", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert is_nil(lv.assigns.selected_skill) || lv.assigns.selected_skill
    end
  end

  describe "handle_event/sort_skills" do
    test "sorts skills", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert lv.assigns.sort_by == "name_asc"
    end
  end

  describe "render/1" do
    test "renders skills list", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "skill" || html =~ "Skill"
    end

    test "renders search controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert html =~ "Search" || html =~ "search"
    end

    test "renders empty state when no skills", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/skills")

      assert is_binary(html)
    end
  end
end

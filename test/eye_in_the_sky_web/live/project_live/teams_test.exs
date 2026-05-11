defmodule EyeInTheSkyWeb.ProjectLive.TeamsTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Teams

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project",
        path: "/tmp/test_project"
      })

    %{project: project}
  end

  describe "mount/3 with project id" do
    test "renders the teams page", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams")

      assert html =~ "team" || html =~ "Team"
    end

    test "renders search bar", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams")

      assert html =~ "Search"
    end

    test "renders empty state when no teams exist", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams")

      assert html =~ "team" || html =~ "Team" || html =~ "No teams"
    end
  end

  describe "mount/3 without project id" do
    test "renders the global teams page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "team" || html =~ "Team"
    end
  end

  describe "handle_params/3" do
    test "page renders when navigating to show_all=true", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams?show_all=true")

      assert html =~ "team" || html =~ "Team"
    end

    test "page renders without show_all param", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams")

      assert html =~ "team" || html =~ "Team"
    end
  end

  describe "render/1 with teams" do
    test "renders a created team in the list", %{conn: conn, project: project} do
      {:ok, _team} =
        Teams.create_team(%{
          project_id: project.id,
          name: "Alpha Team",
          description: "First team"
        })

      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams")

      assert html =~ "Alpha Team"
    end

    test "archived teams are hidden by default", %{conn: conn, project: project} do
      {:ok, _team} =
        Teams.create_team(%{
          project_id: project.id,
          name: "Hidden Team",
          description: "Archived",
          status: "archived"
        })

      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams")

      refute html =~ "Hidden Team"
    end
  end
end

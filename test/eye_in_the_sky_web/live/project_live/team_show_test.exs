defmodule EyeInTheSkyWeb.ProjectLive.TeamShowTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Projects, Teams}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp uniq, do: System.unique_integer([:positive])

  defp create_project(user) do
    n = uniq()

    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project #{n}",
        slug: "test-project-#{n}",
        path: "/tmp/project-#{n}",
        active: true,
        workspace_id: EyeInTheSky.Workspaces.default_workspace_for_user!(user).id
      })

    project
  end

  defp create_team(project, attrs \\ %{}) do
    {:ok, team} =
      Teams.create_team(
        Map.merge(
          %{
            name: "Team #{uniq()}",
            status: "active",
            project_id: project.id
          },
          attrs
        )
      )

    team
  end

  # ---------------------------------------------------------------------------
  # Tests: Cross-project access vulnerability
  # ---------------------------------------------------------------------------

  describe "TeamShow — project_id ownership check" do
    test "allows access to team within correct project", %{conn: conn, user: user} do
      project = create_project(user)
      team = create_team(project)

      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams/#{team.id}")

      # Team name should be visible, not "Team not found"
      assert html =~ team.name
      refute html =~ "Team not found"
    end

    test "prevents access to team from different project", %{conn: conn, user: user} do
      project_a = create_project(user)
      project_b = create_project(user)

      # Create team in project A
      team_a = create_team(project_a)

      # Try to access team A through project B's route
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project_b.id}/teams/#{team_a.id}")

      # Should see "Team not found" error
      assert html =~ "Team not found"
      refute html =~ team_a.name
    end

    test "shows back link to correct project teams page", %{conn: conn, user: user} do
      project = create_project(user)
      team = create_team(project)

      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams/#{team.id}")

      # Back link should navigate to the correct project's teams page
      assert html =~ "/projects/#{project.id}/teams"
    end

    test "returns 404 for non-existent team", %{conn: conn, user: user} do
      project = create_project(user)

      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams/999999")

      assert html =~ "Team not found"
    end

    test "global team (nil project_id) cannot be accessed via project route", %{
      conn: conn,
      user: user
    } do
      project = create_project(user)

      # Create a team with no project_id (global team)
      {:ok, global_team} = Teams.create_team(%{name: "Global Team", project_id: nil})

      # Try to access global team through a project route
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/teams/#{global_team.id}")

      # Should be rejected
      assert html =~ "Team not found"
    end
  end
end

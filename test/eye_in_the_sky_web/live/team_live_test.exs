defmodule EyeInTheSkyWeb.TeamLive.IndexTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  # /teams LiveView removed; route no longer exists
  @moduletag :skip

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Sessions, Teams}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp uniq, do: System.unique_integer([:positive])

  defp create_team(attrs \\ %{}) do
    {:ok, team} =
      Teams.create_team(Map.merge(%{name: "Team #{uniq()}", status: "active"}, attrs))

    team
  end

  defp create_member(team, attrs \\ %{}) do
    {:ok, member} =
      Teams.join_team(Map.merge(%{team_id: team.id, name: "Agent #{uniq()}"}, attrs))

    member
  end

  defp create_member_with_session(team) do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test agent #{uniq()}",
        source: "test"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Session #{uniq()}",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, member} =
      Teams.join_team(%{
        team_id: team.id,
        name: "Agent #{uniq()}",
        session_id: session.id,
        status: "active"
      })

    {member, session}
  end

  # ---------------------------------------------------------------------------
  # Mount / layout
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "renders page with sessions-style layout", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "max-w-4xl"
      assert html =~ "teams"
    end

    test "list view visible and detail view hidden on load", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/teams")

      # Detail div has class="hidden" when mobile_view == :list
      assert html =~ ~s(class="hidden")
      # The toggle archived button is in the list view (proves it is rendered)
      assert html =~ ~s(phx-click="toggle_archived")
    end

    test "shows empty state when no teams exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "No active teams"
    end

    test "renders team rows", %{conn: conn} do
      create_team(%{name: "My Visible Team"})

      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "My Visible Team"
    end

    test "shows member count on team rows", %{conn: conn} do
      team = create_team()
      create_member(team)
      create_member(team)

      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "2 members"
    end

    test "shows active member count when members are active", %{conn: conn} do
      team = create_team()
      create_member(team, %{name: "Active One #{uniq()}", status: "active"})
      create_member(team, %{name: "Idle One #{uniq()}", status: "idle"})

      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "1 active"
    end
  end

  # ---------------------------------------------------------------------------
  # Search
  # ---------------------------------------------------------------------------

  describe "search" do
    test "filters teams by name", %{conn: conn} do
      create_team(%{name: "Phoenix Team #{uniq()}"})
      create_team(%{name: "Elixir Squad #{uniq()}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html = lv |> element("form[phx-change='search']") |> render_change(%{search: "Phoenix"})

      assert html =~ "Phoenix Team"
      refute html =~ "Elixir Squad"
    end

    test "shows empty state when search matches nothing", %{conn: conn} do
      create_team(%{name: "Real Team #{uniq()}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html =
        lv |> element("form[phx-change='search']") |> render_change(%{search: "zzznomatch"})

      assert html =~ "No teams match your search"
    end

    test "search is case-insensitive", %{conn: conn} do
      n = uniq()
      create_team(%{name: "Alpha Squad #{n}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html =
        lv |> element("form[phx-change='search']") |> render_change(%{search: "ALPHA"})

      assert html =~ "Alpha Squad #{n}"
    end

    test "clearing search restores all teams", %{conn: conn} do
      n = uniq()
      create_team(%{name: "Team A #{n}"})
      create_team(%{name: "Team B #{n}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      lv |> element("form[phx-change='search']") |> render_change(%{search: "Team A"})
      html = lv |> element("form[phx-change='search']") |> render_change(%{search: ""})

      assert html =~ "Team A #{n}"
      assert html =~ "Team B #{n}"
    end
  end

  # ---------------------------------------------------------------------------
  # Toggle archived
  # ---------------------------------------------------------------------------

  describe "toggle archived" do
    test "active teams shown by default, archived hidden", %{conn: conn} do
      create_team(%{name: "Active Team #{uniq()}", status: "active"})
      create_team(%{name: "Old Team #{uniq()}", status: "archived"})

      {:ok, _lv, html} = live(conn, ~p"/teams")

      assert html =~ "Active Team"
      refute html =~ "Old Team"
    end

    test "toggling archived reveals archived teams", %{conn: conn} do
      n = uniq()
      create_team(%{name: "Old Team #{n}", status: "archived"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html = lv |> element("[phx-click='toggle_archived']") |> render_click()

      assert html =~ "Old Team #{n}"
    end

    test "button label toggles between show/hide", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/teams")
      assert html =~ "Show archived"

      html = lv |> element("[phx-click='toggle_archived']") |> render_click()
      assert html =~ "Hide archived"
    end
  end

  # ---------------------------------------------------------------------------
  # Team selection / detail view
  # ---------------------------------------------------------------------------

  describe "team selection" do
    test "selecting a team switches to detail view", %{conn: conn} do
      n = uniq()
      team = create_team(%{name: "Detail Team #{n}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html =
        lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()

      assert html =~ "Detail Team #{n}"
      assert html =~ ~s(phx-click="close_team")
    end

    test "close_team returns to list view", %{conn: conn} do
      team = create_team()

      {:ok, lv, _html} = live(conn, ~p"/teams")

      lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()
      lv |> element("[phx-click='close_team']") |> render_click()

      # selected_team is nil — TeamDetailComponent is not rendered
      refute has_element?(lv, "#team-detail")
    end

    test "selecting a different team replaces the detail view", %{conn: conn} do
      n = uniq()
      team_a = create_team(%{name: "First Team #{n}"})
      team_b = create_team(%{name: "Second Team #{n}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      lv |> element("[phx-click='select_team'][phx-value-id='#{team_a.id}']") |> render_click()
      lv |> element("[phx-click='select_team'][phx-value-id='#{team_b.id}']") |> render_click()

      # team-detail component re-renders with team_b — heading should show team_b's name
      assert has_element?(lv, "#team-detail")
      # team_b is now selected (detail component renders its content)
      assert render(lv) =~ "Second Team #{n}"
    end
  end

  # ---------------------------------------------------------------------------
  # Delete team
  # ---------------------------------------------------------------------------

  describe "delete team" do
    test "deletes team and removes it from the list", %{conn: conn} do
      n = uniq()
      team = create_team(%{name: "To Delete #{n}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html =
        lv |> element("[phx-click='delete_team'][phx-value-id='#{team.id}']") |> render_click()

      refute html =~ "To Delete #{n}"
    end

    test "deleting the selected team closes the detail view", %{conn: conn} do
      team = create_team()

      {:ok, lv, _html} = live(conn, ~p"/teams")

      lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()
      lv |> element("[phx-click='delete_team'][phx-value-id='#{team.id}']") |> render_click()

      refute has_element?(lv, "#team-detail")
    end
  end

  # ---------------------------------------------------------------------------
  # select_agent → open_fab_chat push event
  # ---------------------------------------------------------------------------

  describe "select_agent" do
    test "pushes open_fab_chat event with session uuid, name, status", %{conn: conn} do
      team = create_team()
      {member, session} = create_member_with_session(team)

      {:ok, lv, _html} = live(conn, ~p"/teams")
      lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()

      lv |> render_hook("select_agent", %{"id" => to_string(member.session_id)})

      assert_push_event(lv, "open_fab_chat", %{
        session_id: session_id,
        name: name,
        status: _status
      })

      assert session_id == to_string(session.uuid)
      assert name == member.name
    end

    test "does not crash when member has no session", %{conn: conn} do
      team = create_team()
      member = create_member(team, %{status: "idle"})

      {:ok, lv, _html} = live(conn, ~p"/teams")
      lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()

      # Should not raise
      lv |> render_hook("select_agent", %{"id" => to_string(member.session_id || 0)})
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time PubSub updates
  # ---------------------------------------------------------------------------

  describe "real-time updates" do
    test "new team appears after team_created broadcast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/teams")

      n = uniq()
      {:ok, _} = Teams.create_team(%{name: "Live New Team #{n}", status: "active"})

      :timer.sleep(50)

      assert render(lv) =~ "Live New Team #{n}"
    end

    test "team disappears after team_deleted broadcast", %{conn: conn} do
      n = uniq()
      team = create_team(%{name: "Will Be Deleted #{n}"})

      {:ok, lv, _html} = live(conn, ~p"/teams")
      assert render(lv) =~ "Will Be Deleted #{n}"

      Teams.delete_team(team)
      :timer.sleep(50)

      refute render(lv) =~ "Will Be Deleted #{n}"
    end
  end
end

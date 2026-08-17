defmodule EyeInTheSkyWeb.Components.RailTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias EyeInTheSky.Projects

  defp build_project(name \\ nil) do
    name = name || "rail-test-#{System.unique_integer([:positive])}"
    {:ok, project} = Projects.create_project(%{name: name, path: "/tmp/#{name}", slug: name})
    project
  end

  # The Rail is mounted as an embedded live_render (id: "app-rail") inside the
  # app layout. Its events must be dispatched through the child view obtained via
  # find_live_child/2 — dispatching via the parent view sends events to the
  # parent's handle_event/3, which does not handle Rail-specific events.
  defp get_rail(view), do: find_live_child(view, "app-rail")

  describe "select_project — no-op reselect guard" do
    test "closes proj_picker after selecting a project", %{conn: conn} do
      project = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")
      rail = get_rail(view)

      rail |> element("[phx-click='toggle_proj_picker']") |> render_click()
      assert has_element?(view, "[phx-click='select_project']")

      # Selecting a project triggers push_navigate → live_redirect to /projects/:id/sessions.
      # The view process shuts down after sending the redirect; follow it to get the new view.
      {:ok, view2, _html} =
        rail
        |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
        |> render_click()
        |> follow_redirect(conn)

      refute has_element?(view2, "[phx-click='select_project']")
    end

    test "reselecting the same project closes picker without crash", %{conn: conn} do
      project = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")
      rail = get_rail(view)

      rail |> element("[phx-click='toggle_proj_picker']") |> render_click()

      # First select navigates to the project page.
      {:ok, view2, _html} =
        rail
        |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
        |> render_click()
        |> follow_redirect(conn)

      # Re-open picker on the project page.
      rail2 = get_rail(view2)
      rail2 |> element("[phx-click='toggle_proj_picker']") |> render_click()
      assert has_element?(view2, "[phx-click='select_project']")

      # Click select_project again (same project). The Rail's embedded LiveView is a
      # fresh process after the redirect — its sidebar_project may be nil if it
      # subscribed to rail:context after the Sessions LV's connected-mount broadcast.
      # If sidebar_project is nil it selects (not deselects) and navigates again.
      # Either way: no crash + picker closed.
      click_result =
        rail2
        |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
        |> render_click()

      case click_result do
        {:error, {:live_redirect, _}} = redirect ->
          # Rail navigated (treated click as new selection). Follow and verify no crash.
          {:ok, view3, _html} = follow_redirect(redirect, conn)
          refute has_element?(get_rail(view3), "[phx-click='select_project']")

        _html ->
          # Rail deselected in place — picker closed on view2.
          refute has_element?(view2, "[phx-click='select_project']")
      end
    end

    test "selecting a different project closes picker", %{conn: conn} do
      p1 = build_project()
      p2 = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")
      rail = get_rail(view)

      rail |> element("[phx-click='toggle_proj_picker']") |> render_click()

      # Select first project — navigates.
      {:ok, view2, _html} =
        rail
        |> element("[phx-click='select_project'][phx-value-project_id='#{p1.id}']")
        |> render_click()
        |> follow_redirect(conn)

      # Re-open picker and select a different project — navigates again.
      rail2 = get_rail(view2)
      rail2 |> element("[phx-click='toggle_proj_picker']") |> render_click()

      {:ok, view3, _html} =
        rail2
        |> element("[phx-click='select_project'][phx-value-project_id='#{p2.id}']")
        |> render_click()
        |> follow_redirect(conn)

      refute has_element?(view3, "[phx-click='select_project']")
    end

    test "selecting a different project from a project page navigates to that project", %{
      conn: conn
    } do
      p1 = build_project()
      p2 = build_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{p1.id}/tasks")
      rail = get_rail(view)

      rail |> element("[phx-click='toggle_proj_picker']") |> render_click()

      {:ok, _view2, _html} =
        rail
        |> element("[phx-click='select_project'][phx-value-project_id='#{p2.id}']")
        |> render_click()
        |> follow_redirect(conn, ~p"/projects/#{p2.id}/tasks")
    end

    test "restored project selection wins over a stale project route", %{conn: conn} do
      p1 = build_project()
      p2 = build_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{p1.id}/tasks")
      rail = get_rail(view)

      {:ok, _view2, _html} =
        rail
        |> render_hook("restore_rail_state", %{"project_id" => p2.id, "section" => "tasks"})
        |> follow_redirect(conn, ~p"/projects/#{p2.id}/tasks")
    end
  end
end

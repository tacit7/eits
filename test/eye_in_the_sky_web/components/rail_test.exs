defmodule EyeInTheSkyWeb.Components.RailTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias EyeInTheSky.Projects
  alias EyeInTheSky.{Sessions, Tasks}
  alias EyeInTheSky.Workspaces

  # Most interaction tests use projects in the logged-in user's workspace so
  # navigation and restored context are deterministic.
  defp build_project(user, name \\ nil) do
    name = name || "rail-test-#{System.unique_integer([:positive])}"
    workspace = Workspaces.default_workspace_for_user!(user)

    {:ok, project} =
      Projects.create_project(%{
        name: name,
        path: "/tmp/#{name}",
        slug: name,
        workspace_id: workspace.id
      })

    project
  end

  # The Rail is mounted as an embedded live_render (id: "app-rail") inside the
  # app layout. Its events must be dispatched through the child view obtained via
  # find_live_child/2 — dispatching via the parent view sends events to the
  # parent's handle_event/3, which does not handle Rail-specific events.
  defp get_rail(view), do: find_live_child(view, "app-rail")

  describe "flyout chevron toggle" do
    test "tasks rail item navigates to workspace tasks without selected project", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sessions")
      rail = get_rail(view)

      assert {:error, {:live_redirect, %{to: "/tasks"}}} =
               rail
               |> element(~s(button[aria-label="Tasks"]))
               |> render_click()
    end

    test "settings link preserves the current project sessions destination", %{
      conn: conn,
      user: user
    } do
      project = build_project(user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      assert has_element?(
               get_rail(view),
               ~s(a[aria-label="Settings"][href="/settings?return_to=%2Fprojects%2F#{project.id}%2Fsessions"])
             )
    end

    test "renders a persistent desktop chevron for hiding or showing the flyout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sessions")

      assert has_element?(
               get_rail(view),
               "#rail-icon-strip #rail-collapse-toggle[phx-click='toggle_collapsed'][aria-label='Hide flyout menu'] .hero-chevron-double-left"
             )
    end

    test "mobile chevron opens and closes the flyout without relying on swipe", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sessions")
      rail = get_rail(view)

      assert has_element?(
               rail,
               "#rail-icon-strip #rail-mobile-flyout-toggle[phx-click='open_mobile'][aria-label='Show flyout menu'] .hero-chevron-double-right"
             )

      rail
      |> element("#rail-mobile-flyout-toggle")
      |> render_click()

      assert has_element?(
               rail,
               "#rail-icon-strip #rail-mobile-flyout-toggle[phx-click='close_flyout'][aria-label='Hide flyout menu'] .hero-chevron-double-left"
             )

      rail
      |> element("#rail-mobile-flyout-toggle")
      |> render_click()

      assert has_element?(
               rail,
               "#rail-icon-strip #rail-mobile-flyout-toggle[phx-click='open_mobile'][aria-label='Show flyout menu'] .hero-chevron-double-right"
             )
    end
  end

  describe "select_project — no-op reselect guard" do
    test "command palette project submenu includes projects added after mount", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/sessions")

      project = build_project(user, "late-palette-#{System.unique_integer([:positive])}")
      foreign_project = build_project(EyeInTheSky.Factory.user_fixture())
      inactive_project = build_project(user)
      {:ok, _} = Projects.update_project(inactive_project, %{active: false})

      render_hook(view, "palette:projects", %{})

      assert_push_event(view, "palette:projects-result", %{projects: projects})
      assert Enum.any?(projects, &(&1.id == project.id))
      assert Enum.any?(projects, &(&1.id == foreign_project.id))
      refute Enum.any?(projects, &(&1.id == inactive_project.id))
    end

    test "project switcher lists projects from other workspaces", %{conn: conn} do
      other_user = EyeInTheSky.Factory.user_fixture()

      foreign_project =
        build_project(other_user, "foreign-rail-#{System.unique_integer([:positive])}")

      {:ok, view, _html} = live(conn, ~p"/sessions")
      rail = get_rail(view)

      rail |> element("[phx-click='toggle_proj_picker']") |> render_click()

      assert has_element?(
               view,
               "[phx-click='select_project'][phx-value-project_id='#{foreign_project.id}']"
             )
    end

    test "closes proj_picker after selecting a project", %{conn: conn, user: user} do
      project = build_project(user)
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

    test "reselecting the same project closes picker without crash", %{conn: conn, user: user} do
      project = build_project(user)
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

    test "selecting a different project closes picker", %{conn: conn, user: user} do
      p1 = build_project(user)
      p2 = build_project(user)
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
      conn: conn,
      user: user
    } do
      p1 = build_project(user)
      p2 = build_project(user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{p1.id}/tasks")
      rail = get_rail(view)

      rail |> element("[phx-click='toggle_proj_picker']") |> render_click()

      {:ok, _view2, _html} =
        rail
        |> element("[phx-click='select_project'][phx-value-project_id='#{p2.id}']")
        |> render_click()
        |> follow_redirect(conn, ~p"/projects/#{p2.id}/tasks")
    end

    test "restored project selection wins over a stale project route", %{conn: conn, user: user} do
      p1 = build_project(user)
      p2 = build_project(user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{p1.id}/tasks")
      rail = get_rail(view)

      {:ok, _view2, _html} =
        rail
        |> render_hook("restore_rail_state", %{"project_id" => p2.id, "section" => "tasks"})
        |> follow_redirect(conn, ~p"/projects/#{p2.id}/tasks")
    end
  end

  describe "live flyout updates" do
    test "session status changes update the flyout and deletion removes the row", %{
      conn: conn,
      user: user
    } do
      project = build_project(user)
      agent = EyeInTheSky.Factory.create_agent(%{project_id: project.id})

      session =
        EyeInTheSky.Factory.create_session(agent, %{
          project_id: project.id,
          name: "Rail live session",
          status: "working"
        })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")
      rail = get_rail(view)
      render_click(rail, "open_flyout", %{"section" => "sessions"})

      assert has_element?(rail, "#rail-session-#{session.id} .bg-success")

      {:ok, idle_session} = Sessions.set_session_idle(session)
      assert has_element?(rail, "#rail-session-#{session.id} .bg-base-content\\/25")

      {:ok, _deleted_session} = Sessions.delete_session(idle_session)
      refute has_element?(rail, "#rail-session-#{session.id}")
    end

    test "task state changes and deletion refresh the filtered flyout", %{
      conn: conn,
      user: user
    } do
      project = build_project(user)

      {:ok, task} =
        Tasks.create_task(%{
          title: "Rail live task",
          project_id: project.id,
          state_id: 1
        })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")
      rail = get_rail(view)
      render_click(rail, "open_flyout", %{"section" => "tasks"})
      render_click(rail, "set_task_state_filter", %{"state" => "1"})

      assert has_element?(rail, "#rail-task-#{task.id}")

      {:ok, in_progress_task} = Tasks.update_task_state(task, 2)

      refute has_element?(rail, "#rail-task-#{task.id}")

      render_click(rail, "set_task_state_filter", %{"state" => "all"})
      assert has_element?(rail, "#rail-task-#{task.id}")

      {:ok, _deleted_task} = Tasks.delete_task(in_progress_task)

      refute has_element?(rail, "#rail-task-#{task.id}")
    end
  end
end

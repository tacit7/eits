defmodule EyeInTheSkyWeb.Components.RailTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias EyeInTheSky.Projects

  defp build_project(name \\ nil) do
    name = name || "rail-test-#{System.unique_integer([:positive])}"
    {:ok, project} = Projects.create_project(%{name: name, path: "/tmp/#{name}", slug: name})
    project
  end

  describe "select_project — no-op reselect guard" do
    test "closes proj_picker after selecting a project", %{conn: conn} do
      project = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")

      view |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()
      assert has_element?(view, "[phx-click='select_project']")

      # Selecting a project triggers push_navigate → live_redirect to /projects/:id/sessions.
      # The view process shuts down after sending the redirect; follow it to get the new view.
      {:ok, view2, _html} =
        view
        |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
        |> render_click()
        |> follow_redirect(conn)

      refute has_element?(view2, "[phx-click='select_project']")
    end

    test "reselecting the same project closes picker without crash", %{conn: conn} do
      project = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")

      view |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()

      # First select navigates to the project page.
      {:ok, view2, _html} =
        view
        |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
        |> render_click()
        |> follow_redirect(conn)

      # Re-open picker and reselect the same project — this is a de-select (no navigate).
      view2 |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()
      assert has_element?(view2, "[phx-click='select_project']")

      view2
      |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
      |> render_click()

      refute has_element?(view2, "[phx-click='select_project']")
    end

    test "selecting a different project closes picker", %{conn: conn} do
      p1 = build_project()
      p2 = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")

      view |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()

      # Select first project — navigates.
      {:ok, view2, _html} =
        view
        |> element("[phx-click='select_project'][phx-value-project_id='#{p1.id}']")
        |> render_click()
        |> follow_redirect(conn)

      # Re-open picker and select a different project — navigates again.
      view2 |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()

      {:ok, view3, _html} =
        view2
        |> element("[phx-click='select_project'][phx-value-project_id='#{p2.id}']")
        |> render_click()
        |> follow_redirect(conn)

      refute has_element?(view3, "[phx-click='select_project']")
    end
  end
end

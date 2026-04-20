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

      view
      |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
      |> render_click()

      refute has_element?(view, "[phx-click='select_project']")
    end

    test "reselecting the same project closes picker without crash", %{conn: conn} do
      project = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")

      view |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()
      view
      |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
      |> render_click()

      view |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()
      assert has_element?(view, "[phx-click='select_project']")

      view
      |> element("[phx-click='select_project'][phx-value-project_id='#{project.id}']")
      |> render_click()

      refute has_element?(view, "[phx-click='select_project']")
    end

    test "selecting a different project closes picker", %{conn: conn} do
      p1 = build_project()
      p2 = build_project()
      {:ok, view, _html} = live(conn, ~p"/sessions")

      view |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()
      view
      |> element("[phx-click='select_project'][phx-value-project_id='#{p1.id}']")
      |> render_click()

      view |> element("[phx-click='toggle_proj_picker'][phx-target]") |> render_click()
      view
      |> element("[phx-click='select_project'][phx-value-project_id='#{p2.id}']")
      |> render_click()

      refute has_element?(view, "[phx-click='select_project']")
    end
  end
end

defmodule EyeInTheSkyWeb.Live.MobileNavIntegrationTest do
  @moduledoc """
  Regression tests for mobile bottom-nav active-state accuracy across routes.

  Verifies that the correct nav tab is highlighted after LiveView mount and
  after LiveView patch (navigate) updates, since both trigger handle_params.
  """
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "nav-test-#{uniq()}",
        path: "/tmp/nav-test-#{uniq()}",
        slug: "nav-test-#{uniq()}"
      })

    project
  end

  # Checks which mobile nav tab is active by looking for aria-current="page"
  # using CSS attribute selectors (order-independent).
  defp active_nav_tab(view) do
    cond do
      has_element?(view, ~s([aria-current="page"][aria-label="Sessions"])) -> :sessions
      has_element?(view, ~s([aria-current="page"][aria-label="Tasks"])) -> :tasks
      has_element?(view, ~s([aria-current="page"][aria-label="Notes"])) -> :notes
      has_element?(view, ~s([aria-current="page"][aria-label="Project"])) -> :project
      true -> :none
    end
  end

  describe "global routes" do
    test "Sessions tab active on /", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert active_nav_tab(view) == :sessions
    end

    @tag :skip
    test "Tasks tab active on /tasks", %{conn: conn} do
      # /tasks is a REST controller, not a LiveView — no global tasks LiveView exists
      {:ok, view, _html} = live(conn, ~p"/tasks")
      assert active_nav_tab(view) == :tasks
    end

    @tag :skip
    test "Notes tab active on /notes", %{conn: conn} do
      # /notes is a REST controller, not a LiveView — no global notes LiveView exists
      {:ok, view, _html} = live(conn, ~p"/notes")
      assert active_nav_tab(view) == :notes
    end

    test "no tab active on /usage", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/usage")
      assert active_nav_tab(view) == :none
    end

    test "no tab active on /settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      assert active_nav_tab(view) == :none
    end
  end

  describe "project routes — Project tab must be active" do
    test "Project tab active on /projects/:id", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")
      assert active_nav_tab(view) == :project
    end

    test "Project tab active on /projects/:id/sessions", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")
      assert active_nav_tab(view) == :project
    end

    test "Project tab active on /projects/:id/tasks", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")
      assert active_nav_tab(view) == :project
    end

    test "Project tab active on /projects/:id/kanban", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")
      assert active_nav_tab(view) == :project
    end

    test "Project tab active on /projects/:id/notes", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/notes")
      assert active_nav_tab(view) == :project
    end
  end

  describe "Session tab does NOT activate on project sub-routes" do
    test "Sessions tab inactive on /projects/:id/sessions", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")
      refute active_nav_tab(view) == :sessions
    end

    test "Tasks tab inactive on /projects/:id/tasks", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")
      refute active_nav_tab(view) == :tasks
    end

    test "Notes tab inactive on /projects/:id/notes", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/notes")
      refute active_nav_tab(view) == :notes
    end
  end
end

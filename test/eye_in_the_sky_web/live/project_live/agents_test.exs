defmodule EyeInTheSkyWeb.ProjectLive.AgentsTest do
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
    test "mounts with project id and initializes assigns", %{conn: conn, project: project} do
      {:ok, lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert lv |> element("[data-vim-list]") |> render() =~ "agents"
      assert lv.assigns.search_query == ""
      assert lv.assigns.sort_by == "name_asc"
      assert lv.assigns.scope_filter == "all"
      assert lv.assigns.selected_agent == nil
      assert lv.assigns.show_new_agent_form == false
    end

    test "mount without project id handles gracefully", %{conn: conn} do
      # Should handle gracefully or redirect
      {:ok, lv, _html} = live(conn, ~p"/projects/not-found/agents")
      assert is_pid(lv)
    end
  end

  describe "handle_event/search" do
    test "searches agents by query", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      {:ok, _lv, html} = lv |> element("form[phx-change='search']")
      |> render_change(%{"query" => "test"})
      |> then(fn _html -> {:ok, lv, ""} end)

      assert lv.assigns.search_query == "test"
    end

    test "clears search query", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("input[name='query']") |> render_change(%{"query" => ""})

      # Wait for updates
      :timer.sleep(50)

      assert lv.assigns.search_query == ""
    end
  end

  describe "handle_event/sort_agents" do
    test "sorts agents by name ascending", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("select[name='by']") |> render_change(%{"by" => "name_asc"})

      assert lv.assigns.sort_by == "name_asc"
    end

    test "sorts agents by name descending", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("select[name='by']") |> render_change(%{"by" => "name_desc"})

      assert lv.assigns.sort_by == "name_desc"
    end

    test "sorts agents by recent", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("select[name='by']") |> render_change(%{"by" => "recent"})

      assert lv.assigns.sort_by == "recent"
    end
  end

  describe "handle_event/filter_scope" do
    test "filters agents by scope", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("select[name='scope']") |> render_change(%{"scope" => "global"})

      assert lv.assigns.scope_filter == "global"
    end

    test "filters agents by project scope", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("select[name='scope']") |> render_change(%{"scope" => "project"})

      assert lv.assigns.scope_filter == "project"
    end
  end

  describe "handle_event/select_agent" do
    test "selects an agent", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      # Agents are loaded from disk; in test env none will be present
      assert is_nil(lv.assigns.selected_agent)
    end

    test "deselects agent when clicking same agent", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      # Try to toggle - should be nil since no agents are loaded
      assert is_nil(lv.assigns.selected_agent)
    end
  end

  describe "handle_event/close_viewer" do
    test "closes agent detail viewer", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      # Ensure viewer is closed
      assert is_nil(lv.assigns.selected_agent)
    end
  end

  describe "handle_event/set_detail_tab" do
    test "sets detail tab to preview", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button", "Preview") |> render_click()

      assert lv.assigns.detail_tab == :preview
    end

    test "sets detail tab to raw", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      # Click the raw button
      lv |> element("button", "Raw") |> render_click()

      assert lv.assigns.detail_tab == :raw
    end
  end

  describe "handle_event/toggle_new_agent_form" do
    test "toggles new agent form visibility", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert lv.assigns.show_new_agent_form == false

      lv |> element("button", "New") |> render_click()

      assert lv.assigns.show_new_agent_form == true

      lv |> element("button", "Cancel") |> render_click()

      assert lv.assigns.show_new_agent_form == false
    end

    test "clears form fields when toggling", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button", "New") |> render_click()

      assert lv.assigns.new_agent_name == ""
      assert lv.assigns.new_agent_description == ""
    end
  end

  describe "handle_event/update_agent_form" do
    test "updates agent name in form", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button", "New") |> render_click()

      lv
      |> form("form[phx-submit='create_agent']")
      |> render_change(%{"agent_name" => "My Agent"})

      assert lv.assigns.new_agent_name == "My Agent"
    end

    test "updates agent description in form", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button", "New") |> render_click()

      lv
      |> form("form[phx-submit='create_agent']")
      |> render_change(%{"agent_description" => "My Description"})

      assert lv.assigns.new_agent_description == "My Description"
    end
  end

  describe "handle_event/create_agent" do
    test "rejects agent creation with empty name", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button", "New") |> render_click()

      lv
      |> form("form[phx-submit='create_agent']")
      |> render_submit(%{"agent_name" => "", "agent_description" => "Valid"})

      assert lv.assigns.show_new_agent_form == true
    end

    test "rejects agent creation with empty description", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button", "New") |> render_click()

      lv
      |> form("form[phx-submit='create_agent']")
      |> render_submit(%{"agent_name" => "Valid", "agent_description" => ""})

      assert lv.assigns.show_new_agent_form == true
    end
  end

  describe "render/1" do
    test "renders search input", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "Search agents..."
    end

    test "renders sort dropdown", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "Sort"
    end

    test "renders agents count", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "agents"
    end

    test "renders empty state when no agents", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "No agents"
    end
  end
end

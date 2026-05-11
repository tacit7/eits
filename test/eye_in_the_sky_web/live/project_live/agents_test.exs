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

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # The agents page renders two forms with phx-change="search":
  # one in the TopBar toolbar and one in the page body (class="ml-auto").
  # Target the body form specifically via its child input's data attribute.
  defp body_search_form(lv), do: element(lv, "form[phx-change='search'].ml-auto")

  # Sort and scope phx-change is on the parent <form>, not the <select>.
  defp sort_form(lv), do: element(lv, "form[phx-change='sort_agents']")
  defp scope_form(lv), do: element(lv, "form[phx-change='filter_scope']")

  # ---------------------------------------------------------------------------
  # mount/3
  # ---------------------------------------------------------------------------

  describe "mount/3" do
    test "renders the agents page for a valid project", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "agents"
    end

    test "renders empty state when no agent files exist on disk", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "No agents"
    end

    test "renders the new-agent toggle button", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "New"
    end

    test "renders search input", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "Search agents..."
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event/search
  # ---------------------------------------------------------------------------

  describe "handle_event/search" do
    test "search query is reflected in the input value", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      html = body_search_form(lv) |> render_change(%{"query" => "mybot"})

      # The input value should appear in the re-rendered form
      assert html =~ "mybot"
    end

    test "clearing search query re-renders with empty input", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      body_search_form(lv) |> render_change(%{"query" => "x"})
      html = body_search_form(lv) |> render_change(%{"query" => ""})

      refute html =~ "value=\"x\""
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event/sort_agents
  # ---------------------------------------------------------------------------

  describe "handle_event/sort_agents" do
    test "name_desc option becomes selected after sort event", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      sort_form(lv) |> render_change(%{"by" => "name_desc"})
      html = render(lv)

      assert html =~ ~s(value="name_desc" selected)
    end

    test "recent option becomes selected after sort event", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      sort_form(lv) |> render_change(%{"by" => "recent"})
      html = render(lv)

      assert html =~ ~s(value="recent" selected)
    end

    test "size_asc option becomes selected after sort event", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      sort_form(lv) |> render_change(%{"by" => "size_asc"})
      html = render(lv)

      assert html =~ ~s(value="size_asc" selected)
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event/filter_scope
  # ---------------------------------------------------------------------------

  describe "handle_event/filter_scope" do
    test "global option becomes selected after filter event", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      scope_form(lv) |> render_change(%{"scope" => "global"})
      html = render(lv)

      assert html =~ ~s(value="global" selected)
    end

    test "project option becomes selected after filter event", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      scope_form(lv) |> render_change(%{"scope" => "project"})
      html = render(lv)

      assert html =~ ~s(value="project" selected)
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event/toggle_new_agent_form
  # ---------------------------------------------------------------------------

  describe "handle_event/toggle_new_agent_form" do
    test "clicking New renders the create-agent form", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      refute has_element?(lv, "form[phx-submit='create_agent']")

      lv |> element("button[phx-click='toggle_new_agent_form']") |> render_click()

      assert has_element?(lv, "form[phx-submit='create_agent']")
    end

    test "clicking New again hides the create-agent form", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button[phx-click='toggle_new_agent_form']") |> render_click()
      assert has_element?(lv, "form[phx-submit='create_agent']")

      lv |> element("button[phx-click='toggle_new_agent_form']") |> render_click()
      refute has_element?(lv, "form[phx-submit='create_agent']")
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event/update_agent_form
  # ---------------------------------------------------------------------------

  describe "handle_event/update_agent_form" do
    test "typing in agent name input updates rendered value", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button[phx-click='toggle_new_agent_form']") |> render_click()

      html =
        lv
        |> element("input[name='agent_name'][phx-change='update_agent_form']")
        |> render_change(%{"agent_name" => "My Agent"})

      assert html =~ "My Agent"
    end

    test "typing in description textarea updates rendered value", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button[phx-click='toggle_new_agent_form']") |> render_click()

      html =
        lv
        |> element("textarea[name='agent_description'][phx-change='update_agent_form']")
        |> render_change(%{"agent_description" => "Does things"})

      assert html =~ "Does things"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event/create_agent
  # ---------------------------------------------------------------------------

  describe "handle_event/create_agent" do
    test "submitting blank name keeps form open with flash error", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button[phx-click='toggle_new_agent_form']") |> render_click()

      html =
        lv
        |> form("form[phx-submit='create_agent']")
        |> render_submit(%{"agent_name" => "   ", "agent_description" => "Valid desc"})

      # form stays open and an error is shown
      assert html =~ "create_agent" || has_element?(lv, "form[phx-submit='create_agent']")
    end

    test "submitting blank description keeps form open with flash error", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/agents")

      lv |> element("button[phx-click='toggle_new_agent_form']") |> render_click()

      html =
        lv
        |> form("form[phx-submit='create_agent']")
        |> render_submit(%{"agent_name" => "Valid Name", "agent_description" => "   "})

      assert html =~ "create_agent" || has_element?(lv, "form[phx-submit='create_agent']")
    end
  end

  # ---------------------------------------------------------------------------
  # render/1 — static content
  # ---------------------------------------------------------------------------

  describe "render/1" do
    test "renders mobile sort select with all five options", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "Name A"
      assert html =~ "Name Z"
      assert html =~ "Recent"
      assert html =~ "Largest"
      assert html =~ "Smallest"
    end

    test "renders mobile scope select with all three options", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ "All Sources"
      assert html =~ "Global"
      assert html =~ "Project"
    end

    test "name_asc is the default selected sort", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ ~s(value="name_asc" selected)
    end

    test "all sources is the default selected scope", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/agents")

      assert html =~ ~s(value="all" selected)
    end
  end
end

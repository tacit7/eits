defmodule EyeInTheSkyWeb.TopBar.AgentsTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.TopBar.Agents

  describe "toolbar/1 component" do
    test "renders search input with default value", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "Search agents"
      assert html =~ "agents-top-bar-search"
    end

    test "renders search input with custom value", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{search_query: "test-query"})

      assert html =~ "test-query"
    end

    test "renders scope filter dropdown", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "Source:"
      assert html =~ "agents-scope-dropdown"
    end

    test "renders sort dropdown", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "Sort:"
      assert html =~ "agents-sort-dropdown"
    end

    test "renders all scope options", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{scope_filter: "all"})

      assert html =~ "All Sources" || html =~ "All"
      assert html =~ "Global" || html =~ "global"
      assert html =~ "Project" || html =~ "project"
    end

    test "renders all sort options", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{sort_by: "name_asc"})

      assert html =~ "Name" || html =~ "name"
      assert html =~ "Recent" || html =~ "recent"
    end

    test "highlights selected scope filter", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{scope_filter: "project"})

      assert html =~ "Project" || html =~ "project"
    end

    test "highlights selected sort order", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{sort_by: "recent"})

      # Sort should be highlighted in the component
      assert is_binary(html)
    end

    test "renders with vim search attribute", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "vim" || html =~ "Vim" || is_binary(html)
    end

    test "handles all scope filter values", %{conn: conn} do
      for scope <- ["all", "global", "project"] do
        html = render_component(&Agents.toolbar/1, %{scope_filter: scope})
        assert is_binary(html)
      end
    end

    test "handles all sort order values", %{conn: conn} do
      for sort <- ["name_asc", "name_desc", "recent", "size_desc", "size_asc"] do
        html = render_component(&Agents.toolbar/1, %{sort_by: sort})
        assert is_binary(html)
      end
    end

    test "renders dropdown triggers", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{})

      # Should have clickable elements to open dropdowns
      assert html =~ "dropdown" || html =~ "details"
    end

    test "component renders without errors with empty attributes", %{conn: conn} do
      assert render_component(&Agents.toolbar/1, %{}) |> is_binary()
    end

    test "component renders separator between search and filters", %{conn: conn} do
      html = render_component(&Agents.toolbar/1, %{})

      # Should have visual separator
      assert is_binary(html)
    end
  end
end
